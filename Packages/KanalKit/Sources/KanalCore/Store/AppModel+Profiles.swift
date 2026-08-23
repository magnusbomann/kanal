import Foundation

/// Profiles, age limits, and the one place the library is narrowed.
///
/// Everything here funnels through `applyPolicy()`. A screen cannot opt out of
/// the age limit, because a screen never sees anything to opt out of — it reads
/// `library`, and `library` is already what this profile is allowed to have.
@MainActor
public extension AppModel {

    // MARK: - Choosing

    /// Whether to open on "who is watching?".
    ///
    /// A household of one, with no code set, is not asked. The promise the app
    /// makes is that it needs no configuration; putting a chooser in front of a
    /// person who has nothing to choose would break that for the majority to
    /// serve the minority.
    var shouldAskWhoIsWatching: Bool {
        profiles.count > 1 || parentalCode.isSet
    }

    /// Switches to a profile and rebuilds everything that depends on who is
    /// watching: their favourites, their history, their library.
    func activate(_ profile: Profile) async {
        guard profiles.contains(where: { $0.id == profile.id }) else { return }

        // Set first, so the pending save from the outgoing profile — and the
        // one this assignment triggers — both land in the right file.
        await flushWatchState()
        activeProfileID = profile.id
        watchState = await storage.load(
            WatchState.self, from: profile.watchStateFileName
        ) ?? WatchState()

        isChoosingProfile = false
        applyPolicy()
        scheduleVerification()
    }

    /// Puts the "who is watching?" screen back up.
    ///
    /// Leaving a restricted profile is the moment the code matters, so the
    /// caller must have collected it. `canLeaveWithoutCode` says whether it
    /// needs asking.
    func beginChoosingProfile() {
        isChoosingProfile = true
    }

    /// Whether the person watching can get back to the chooser unchallenged.
    ///
    /// Only a restricted profile is held, and only when a code exists. A code
    /// nobody set is not a lock, and pretending otherwise would just lock a
    /// parent out of their own app.
    var canLeaveProfileWithoutCode: Bool {
        !(isRestricted && parentalCode.isSet)
    }

    /// Whether changing profiles, playlists or parental settings needs the code.
    var needsCodeForSettings: Bool {
        isRestricted && parentalCode.isSet
    }

    // MARK: - Editing

    func addProfile(_ profile: Profile) async {
        profiles.append(profile)
        await persistProfiles()
    }

    /// Saves an edit. Applying it immediately matters: a parent who has just
    /// tightened a limit should not have to leave the screen to see it take.
    func updateProfile(_ profile: Profile) async {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index] = profile
        await persistProfiles()
        if profile.id == activeProfileID {
            applyPolicy()
            scheduleVerification()
        }
    }

    /// Removes a profile, and their history with it.
    ///
    /// The last profile is never removed — a household with none would have
    /// nobody to own the library, and the app would have to invent one.
    func deleteProfile(_ profile: Profile) async {
        guard profiles.count > 1 else { return }
        profiles.removeAll { $0.id == profile.id }
        await storage.remove(profile.watchStateFileName)
        await persistProfiles()
        if activeProfileID == profile.id, let next = profiles.first {
            await activate(next)
        }
    }

    /// Approves a whole provider category for a profile.
    ///
    /// Approving a section is not approving everything in it forever: entries a
    /// board later rates above the limit drop back out on their own, and adult
    /// material filed inside it never gets in at all.
    func setCategory(_ category: String, allowed: Bool, for profile: Profile) async {
        guard var updated = profiles.first(where: { $0.id == profile.id }) else { return }
        if allowed {
            updated.allowedCategories.insert(category)
        } else {
            updated.allowedCategories.remove(category)
        }
        await updateProfile(updated)
    }

    func setItem(_ item: MediaItem, allowed: Bool, for profile: Profile) async {
        guard var updated = profiles.first(where: { $0.id == profile.id }) else { return }
        let key = RatingKey.of(item)
        if allowed {
            updated.allowedTitleKeys.insert(key)
            updated.blockedTitleKeys.remove(key)
        } else {
            updated.allowedTitleKeys.remove(key)
            updated.blockedTitleKeys.insert(key)
        }
        await updateProfile(updated)
    }

    /// A grown-up's own age limit for a title, which outranks every other
    /// source and applies to every profile in the household.
    func setParentRating(_ rating: MaturityRating, for item: MediaItem) async {
        await ratingService.setParentRating(rating, forKey: RatingKey.of(item))
        ratings = await ratingService.current
        applyPolicy()
    }

    // MARK: - Setting up a code

    /// Sets, changes or clears the parental code. Clearing takes the old one.
    @discardableResult
    func setParentalCode(_ code: String?) -> Bool {
        parentalCode.set(code)
    }

    // MARK: - Applying

    /// Installs a freshly loaded catalogue and narrows it to the active profile.
    ///
    /// Provider age markers are read here, before anything is shown. Doing it
    /// after would leave a restricted profile briefly permissive, which is the
    /// only window that would ever matter.
    func setCatalogue(_ library: Library) async {
        catalogue = library
        if !library.isEmpty {
            ratings = await ratingService.seedProviderMarkers(from: library.items)
        }
        applyPolicy()
        scheduleVerification()
    }

    /// Recomputes the visible library from the catalogue.
    func applyPolicy() {
        // Nobody has chosen yet — the picker is up and no library is on screen.
        // Filtering four hundred thousand entries down to the nothing a
        // non-existent profile may see is work with no reader.
        guard activeProfile != nil else {
            library = .empty
            withheldCount = 0
            return
        }
        let policy = policy
        if policy.isUnrestricted {
            library = catalogue
            withheldCount = 0
        } else {
            library = policy.apply(to: catalogue)
            withheldCount = max(catalogue.items.count - library.items.count, 0)
        }
        scheduleDiscoveryMatching()
    }

    /// Whether an entry is playable by the person watching.
    ///
    /// The library is already filtered, so this is belt and braces — but a
    /// pairing handoff, a deep link or a stale navigation path can all hand the
    /// player an entry that was never on screen, and the player is the last
    /// place to catch that.
    func canPlay(_ item: MediaItem) -> Bool {
        policy.allows(item)
    }

    // MARK: - Verification

    /// Fills in board ratings for what a restricted profile can currently see.
    ///
    /// Only run for restricted profiles, and only in the background. For a
    /// grown-up there is nothing to check, and spending someone's data on
    /// ratings nobody will consult would be rude.
    func scheduleVerification() {
        verificationTask?.cancel()
        ratingsPending = 0
        guard isRestricted, !catalogue.isEmpty else { return }

        let policy = policy
        let catalogue = catalogue

        verificationTask = Task { @MainActor [ratingService] in
            // Let the first screen draw; nothing here is urgent.
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }

            // The pool comes from the **catalogue**, not from `library`.
            //
            // Verifying what was already visible was backwards: it only ever
            // re-confirmed entries a child could see anyway, a slice at a
            // time, and left the rest of an approved section showing
            // unchecked. Family Guy sat thousands of entries down an
            // "Animation" section and was never reached.
            //
            // Built off the main actor. It is a pass over every entry the
            // provider sent — four hundred thousand of them — and each one
            // normalises a title, which is exactly the kind of work that turns
            // into dropped frames if done where the scrolling happens.
            var outstanding = await Self.pool(policy: policy, catalogue: catalogue)
            guard !Task.isCancelled else { return }
            self.ratingsPending = outstanding.count

            while !outstanding.isEmpty {
                guard let progress = await ratingService.verify(outstanding) else { return }
                guard !Task.isCancelled else { return }

                if progress.changed {
                    self.ratings = await ratingService.snapshot
                    self.applyPolicy()
                }
                self.ratingsPending = progress.remaining
                guard progress.remaining > 0 else { return }

                if progress.wasRateLimited {
                    // Backing off rather than hammering: the answers are
                    // permanent, so there is never a reason to be in a hurry.
                    try? await Task.sleep(for: .seconds(20))
                    guard !Task.isCancelled else { return }
                }

                // Narrowed against what is left rather than rebuilt from the
                // catalogue, so the expensive pass happens once.
                let current = self.policy
                let checked = outstanding
                outstanding = await Task.detached(priority: .utility) {
                    current.awaitingRating(among: checked)
                }.value
            }
        }
    }

    private static func pool(policy: ContentPolicy, catalogue: Library) async -> [MediaItem] {
        await Task.detached(priority: .utility) {
            policy.awaitingRating(in: catalogue)
        }.value
    }

    // MARK: - Persistence

    func persistProfiles() async {
        await storage.save(profiles, to: AppModel.profilesFile)
    }

    private func flushWatchState() async {
        guard let current = activeProfile else { return }
        await storage.save(watchState, to: current.watchStateFileName)
    }

    /// Turns a pre-profiles installation into a household of one.
    ///
    /// Their favourites and history move across rather than being re-read from
    /// the old path forever — one migration, done once, instead of a fallback
    /// that has to be remembered every time this code is touched again.
    func adoptExistingHousehold() async {
        let owner = Profile.makeOwner(named: String(localized: CoreStrings.profileDefaultOwnerName))
        profiles = [owner]
        await persistProfiles()

        let existing = await storage.load(WatchState.self, from: WatchState.fileName)
        activeProfileID = owner.id
        watchState = existing ?? WatchState()
        await storage.save(watchState, to: owner.watchStateFileName)
        if existing != nil { await storage.remove(WatchState.fileName) }
    }

    /// The profile created alongside a household's first playlist.
    func createOwnerProfile() async {
        let owner = Profile.makeOwner(named: String(localized: CoreStrings.profileDefaultOwnerName))
        profiles = [owner]
        activeProfileID = owner.id
        await persistProfiles()
    }
}
