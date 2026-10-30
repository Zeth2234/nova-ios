import SwiftUI

struct ContentView: View {
    @StateObject private var model = BrowserModel()
    @State private var showSettings = false
    @State private var showTabs = false

    var body: some View {
        ZStack {
            NovaBackground().ignoresSafeArea()

            VStack(spacing: 0) {
                if model.isHome {
                    HomeTopBar(openSettings: { showSettings = true })
                } else {
                    AddressBar(model: model)
                        .background(NovaTheme.bg.opacity(0.97).ignoresSafeArea(edges: .top))
                }

                ZStack {
                    WebViewContainer(webView: model.webView)
                        .opacity(model.isHome ? 0 : 1)
                        .allowsHitTesting(!model.isHome)
                    if model.isHome {
                        HomeView(model: model)
                    }
                }

                BottomBar(model: model,
                          openSettings: { showSettings = true },
                          openTabs: { showTabs = true })
                    .background(NovaTheme.bg.opacity(0.97).ignoresSafeArea(edges: .bottom))
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showTabs) {
            TabSwitcherView(model: model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}
