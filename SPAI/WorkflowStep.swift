//
//  WorkflowStep.swift
//  SPAI
//
//  Created by AV Student on 4/27/26.
//

import Foundation

struct WorkflowStep: Identifiable {
    let id = UUID()
    let number: Int
    let title: String
    let status: WorkflowStepStatus
}

enum WorkflowStepStatus {
    case active
    case complete
    case locked
}
