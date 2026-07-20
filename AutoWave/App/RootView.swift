import SwiftUI

struct RootView: View {
    var body: some View {
        NavigationStack {
            HomeView()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            NavigationLink("음원 가져오기") {
                                ImportView()
                            }
                            NavigationLink("변환") {
                                AnalysisView()
                            }
                            NavigationLink("게임") {
                                GameplayContainerView()
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .accessibilityLabel("더보기")
                        }
                    }
                }
        }
        .tint(AppTheme.accent)
        .preferredColorScheme(.dark)
    }
}
