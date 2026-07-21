import SwiftUI

struct RootView: View {
    var body: some View {
        NavigationStack {
            SongSelectView()
        }
        .tint(AppTheme.accentPurple)
        .preferredColorScheme(.dark)
    }
}
