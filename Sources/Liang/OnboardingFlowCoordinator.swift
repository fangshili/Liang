// OnboardingFlowCoordinator.swift
// Bridges OnboardingWindowController (AppKit host) with OnboardingRootView (SwiftUI).

import AppKit
import SwiftUI

@MainActor
final class OnboardingFlowCoordinator: ObservableObject {
    static let shared = OnboardingFlowCoordinator()
    private init() {}

    /// The currently presented onboarding window controller, if any.
    weak var host: OnboardingWindowController?

    /// SwiftUI observes this to determine which step content to display.
    @Published var currentStep: Int = 1

    /// Advance the visible step from 1 to 2.
    func advanceToStep2() {
        withAnimation(.easeInOut(duration: 0.35)) {
            currentStep = 2
        }
    }

    /// Regress the visible step from 2 to 1.
    func advanceToStep1() {
        withAnimation(.easeInOut(duration: 0.35)) {
            currentStep = 1
        }
    }

    /// User finished onboarding (Start Using Liang or Skip).
    func complete() {
        host?.complete()
    }
}
