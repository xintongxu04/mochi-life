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
    /// The edges she was near when the ring last opened (memory only), for the ring's hysteresis.
    var menuNearEdges: RadialMenuGeometry.Edges = []
    /// Floating Mochi shows only on the Calories screen with nothing presented over it.
    var isSpriteHidden: Bool { isLoggingFood || isEditingEntry || isRestoring || !path.isEmpty }
    /// Height of the standard inline navigation bar: the row holding the toolbar buttons.
    static let toolbarRowHeight: CGFloat = 44
    /// Gap below the toolbar button row.
    static let toolbarRowGap: CGFloat = 4

    /// The top of the area Mochi and her ring may use, in screen points: just below the toolbar
    /// button row (the window's top safe area + the inline bar + 4 pt). It never includes the
    /// large "Today" title or anything that scrolls, and never changes while scrolling.
    static func topLimit(safeAreaTop: CGFloat) -> CGFloat {
        safeAreaTop + toolbarRowHeight + toolbarRowGap
    }

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

    /// Tapping Mochi opens or closes the ring straight away, and wakes her if she's asleep (she
    /// stretches while the ring opens). It never interrupts her current animation otherwise.
    func spriteTapped() {
        animator.spriteTouched()
        withAnimation(.easeOut(duration: 0.2)) { isMenuOpen.toggle() }
    }

    /// The start of a drag on Mochi: wakes her if she's asleep.
    func spriteDragStarted() {
        isMenuOpen = false
        animator.spriteTouched()
    }

    /// Petting (long-press): closes the ring and grooms, unless she's eating.
    @discardableResult
    func pet() -> Bool {
        isMenuOpen = false
        return animator.pet()
    }

    /// The Play button: playing for 10 loops (about 20 s); tapping again restarts them.
    func playWithBall() {
        animator.playWithBall()
    }

    // MARK: - Eating

    /// Called right after a new food log entry is saved from a logging form (not schedules,
    /// carried days, edits, deletes or restores).
    func foodLogged() {
        pendingEating = true
    }

    /// Plays the eat-then-groom sequence if a food was logged and the Calories screen is showing
    /// with nothing over it, after the sheet has had time to slide away.
    func playEatingIfPending() {
        guard pendingEating, !isSpriteHidden, path.isEmpty else { return }
        pendingEating = false
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            animator.ateFood()
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
