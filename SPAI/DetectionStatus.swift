//
//  DetectionStatus.swift
//  SPAI
//
//  Created by AV Student on 4/27/26.
//

import SwiftUI

enum DetectionStatus: String {
    case safe = "Safe"
    case clear = "Clear"
    case review = "Review"
    case warning = "Warning"
    case critical = "Critical"

    var color: Color {
        switch self {
        case .safe, .clear:
            return .green
        case .review:
            return .blue
        case .warning:
            return .yellow
        case .critical:
            return .red
        }
    }

    var icon: String {
        switch self {
        case .safe, .clear:
            return "checkmark.shield.fill"
        case .review:
            return "eye.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .critical:
            return "xmark.octagon.fill"
        }
    }
}
