// OnboardingPreviewDriver.swift
// Drives the Step 2 glow preview animation: cycles through the three glows and
// three states with a 3-second interval each, looping indefinitely.

import Foundation
import Combine

@MainActor
final class OnboardingPreviewDriver: ObservableObject {
    static let shared = OnboardingPreviewDriver()

    /// Total number of glow cards in the Step 2 preview (Notch / Cursor / MenuBar).
    let totalGlows: Int = 3

    /// 0-based index of the currently-active glow card.
    @Published private(set) var activeIndex: Int = 0

    /// State currently being simulated on the active glow.
    @Published private(set) var activeState: GlowPreviewState = .idle

    private var timer: Timer?
    /// Number of ticks elapsed within the current glow (3 ticks → 3 states).
    private var tickCounter: Int = 0

    private init() {}

    func start() {
        stop()
        // Sync the first state immediately so the active card never flickers idle.
        activeIndex = 0
        activeState = .idle
        tickCounter = 0

        let timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        tickCounter += 1
        if tickCounter > 2 {
            // Move to the next glow, restart from idle state.
            tickCounter = 0
            activeIndex = (activeIndex + 1) % totalGlows
            activeState = .idle
        } else {
            activeState = nextState(after: activeState)
        }
    }

    private func nextState(after state: GlowPreviewState) -> GlowPreviewState {
        switch state {
        case .idle:       return .processing
        case .processing: return .success
        case .success:    return .idle
        }
    }
}
