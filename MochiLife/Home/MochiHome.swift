import Observation
import SwiftUI

/// Screens pushed from the radial menu (and the calorie-estimate shortcuts).
enum AppScreen: Hashable {
    case weight
    case profile
    case settings
}

/// State of the single-screen shell: the navigation path, Mochi's animator, the radial menu,
/// the Log Food sheet, what hides floating Mochi, and the "Mochi eats" signal. Shared through
/// the environment.
@Observable
@MainActor
final class MochiHome {
    var path = NavigationPath()
    let animator = MochiAnimator()
    var isMenuOpen = false
    /// The Log Food sheet; opened by the toolbar button and the ring's Eat button alike.
    var isLoggingFood = false
    /// A log entry's edit sheet is open on the Calories screen.
    var isEditingEntry = false
    /// A backup restore sheet is open.
    var isRestoring = false
    /// Mochi's sprite in global coordinates, for placing the ring.
    var spriteFrame: CGRect = .zero
    /// Floating Mochi shows only on the Calories screen with nothing presented over it.
    var isSpriteHidden: Bool { isLoggingFood || isEditingEntry || isRestoring || !path.isEmpty }
    /// The bottom of the expanded navigation bar on the Calories screen, in screen points: the
    /// fixed top of Mochi's area. Only ever grows, so the bar collapsing while scrolling never
    /// moves it.
    private(set) var restingTopLimit: CGFloat = 0

    func noteRestingTopLimit(_ value: CGFloat) {
        if value > restingTopLimit { restingTopLimit = value }
    }

    static let playLoops = 10
    static let eatingLoops = 6
    /// A food was logged; Mochi eats once the Calories screen is showing again.
    private var pendingEating = false

    // MARK: - Actions

    /// The one code path for opening Log Food.
    func openLogFood() {
        isLoggingFood = true
    }

    func push(_ screen: AppScreen) {
        path.append(screen)
    }

    /// Back to the Calories screen.
    func popToRoot() {
        path = NavigationPath()
    }

    /// Tapping Mochi opens or closes the ring. It never interrupts her current animation.
    func spriteTapped() {
        withAnimation(.easeOut(duration: 0.2)) { isMenuOpen.toggle() }
    }

    /// The Play button: 10 loops (about 20 s); tapping again restarts them.
    func playWithBall() {
        animator.play(.playing, loops: Self.playLoops)
    }

    // MARK: - Eating

    /// Called right after a new food log entry is saved from a logging form (not schedules,
    /// carried days, edits, deletes or restores).
    func foodLogged() {
        pendingEating = true
    }

    /// Plays the eating animation (6 loops, about 12 s) if a food was logged and the Calories
    /// screen is showing with nothing over it, after the sheet has had time to slide away.
    func playEatingIfPending() {
        guard pendingEating, !isSpriteHidden, path.isEmpty else { return }
        pendingEating = false
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            animator.play(.eating, loops: Self.eatingLoops)
        }
    }
}

/// Tells the shell a food log entry was just saved from a logging form.
struct FoodLoggedAction {
    weak var home: MochiHome?

    @MainActor
    func callAsFunction() {
        home?.foodLogged()
    }
}

extension EnvironmentValues {
    @Entry var foodLogged = FoodLoggedAction()
}
