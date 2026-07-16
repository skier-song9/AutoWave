import SwiftUI

struct RootView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink("라이브러리") {
                    LibraryView()
                }
                NavigationLink("음원 가져오기") {
                    ImportView()
                }
                NavigationLink("변환") {
                    AnalysisView()
                }
                NavigationLink("게임") {
                    GameplayContainerView()
                }
            }
            .navigationTitle("AutoWave")
        }
    }
}
