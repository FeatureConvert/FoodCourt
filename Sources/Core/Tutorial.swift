import Foundation

/// A short guided opening for a brand new player. Each step waits for the player to actually
/// perform the action rather than making them tap "Next" through a wall of text, so by the
/// end they have run the whole core loop once themselves.
enum TutorialStep: Int, Codable, CaseIterable, Identifiable {
    case tapStation = 0
    case buyLevel
    case hireManager
    case coffeeBreak
    case openGoals

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .tapStation:  return "Cook something"
        case .buyLevel:    return "Reinvest"
        case .hireManager: return "Hire some help"
        case .coffeeBreak: return "Take a Coffee Break"
        case .openGoals:   return "Know what's next"
        }
    }

    var detail: String {
        switch self {
        case .tapStation:
            return "Tap the Fry Basket to cook a batch. Every batch you serve pays out."
        case .buyLevel:
            return "Spend those coins on a level. Higher levels pay more per batch."
        case .hireManager:
            return "Hire a manager and the station runs itself — even while the app is closed."
        case .coffeeBreak:
            return "Tap the coffee cup for a free ×2 boost. It costs nothing, and there are no ads."
        case .openGoals:
            return "Goals always tell you what to aim at next. Open them to see your first three."
        }
    }

    /// Which control the overlay points at.
    var target: TutorialTarget {
        switch self {
        case .tapStation:  return .stationCooker
        case .buyLevel:    return .stationBuy
        case .hireManager: return .stationHire
        case .coffeeBreak: return .coffeeButton
        case .openGoals:   return .goalsTab
        }
    }
}

/// The controls the tutorial can highlight.
enum TutorialTarget {
    case stationCooker, stationBuy, stationHire, coffeeButton, goalsTab
}

struct TutorialState: Codable, Equatable {
    var step: Int = 0
    var finished: Bool = false

    var current: TutorialStep? {
        finished ? nil : TutorialStep(rawValue: step)
    }

    var isActive: Bool { current != nil }

    /// Advances only when the completed action matches the step being asked for, so a player
    /// doing something else first cannot skip ahead by accident.
    mutating func complete(_ step: TutorialStep) {
        guard !finished, self.step == step.rawValue else { return }
        let next = self.step + 1
        if TutorialStep(rawValue: next) == nil {
            finished = true
        } else {
            self.step = next
        }
    }

    mutating func skip() { finished = true }

    mutating func restart() {
        step = 0
        finished = false
    }

    var progressLabel: String {
        guard let current else { return "" }
        return "\(current.rawValue + 1) of \(TutorialStep.allCases.count)"
    }
}
