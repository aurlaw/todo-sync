#if os(macOS)
import SwiftUI

/// The single text field shared by the menu-bar popover and the hotkey panel: capture only, no list,
/// no editing. `⏎` saves and clears; an empty line does nothing; `Esc` dismisses.
struct CaptureField: View {
    /// Returns whether the text was saved (empty input is not a capture).
    let capture: (String) -> Bool
    let dismiss: () -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("Add a todo", text: $text)
            .textFieldStyle(.plain)
            .font(.title3)
            .focused($isFocused)
            .onSubmit {
                if capture(text) {
                    text = ""
                    dismiss()
                }
            }
            .onExitCommand(perform: dismiss)
            .padding(14)
            .frame(width: 420)
            .task { isFocused = true }
    }
}
#endif
