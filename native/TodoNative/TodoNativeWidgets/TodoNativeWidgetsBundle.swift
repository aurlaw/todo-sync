//
//  TodoNativeWidgetsBundle.swift
//  TodoNativeWidgets
//
//  Created by Michael Lawrence on 9/20/26.
//

import SwiftUI
import WidgetKit

@main
struct TodoNativeWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ActiveListWidget()
        TodayCountWidget()
        #if os(iOS)
        NewTodoControl()
        #endif
    }
}
