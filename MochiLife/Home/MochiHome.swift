import Observation
import SwiftUI

/// Screens pushed from the radial menu (and the calorie-estimate shortcuts).
enum AppScreen: Hashable {
    case weight
    case profile
    case settings
}

/// State of the single-screen shell: the navigation path, Mochi's animator, the radial menu,
/// the Log Food sheet, and the "Mochi eats" signal. Shared through the environment.
@Observable
@MainActor
final class MochiHome {
    var path = NavigationPath()
    let animator = MochiAnimator()
    var isMenuOpen = false
    /// The Log Food sheet; opened by the toolbar button and the ring's Eat button alike.
    var isLoggingFood = false
    /// Mochi's sprite in global coordinates, for placing the ring.
    var spriteFrame: CGRect = .zero
    /// True when the list is scrolled so the sprite may be partly off screen.
    var isSpriteScrolledAway = false
    /// Changes to ask the Calories list to scroll Mochi into view.
    private(set) var scrollToSpriteRequest = 0
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

    /// Tapping Mochi: opens the ring (scrolling her into view first if needed), or closes it.
    func spriteTapped() {
        if isMenuOpen {
            isMenuOpen = false
            return
        }
        if isSpriteScrolledAway {
            scrollToSpriteRequest += 1
            Task {
                try? await Task.sleep(for: .milliseconds(350))
                isMenuOpen = true
            }
        } else {
            isMenuOpen = true
        }
    }

    // MARK: - Eating

    /// Called right after a new food log entry is saved from a logging form (not schedules,
    /// carried days, edits, deletes or restores).
    func foodLogged() {
        pendingEating = true
    }

    /// Plays the eating animation if a food was logged and the Calories screen is showing with
    /// no sheet over it, after the sheet has had time to slide away.
    func playEatingIfPending() {
        guard pendingEating, !isLoggingFood, path.isEmpty else { return }
        pendingEating = false
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            scrollToSpriteRequest += 1
            animator.play(.eating, loops: 2)
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
