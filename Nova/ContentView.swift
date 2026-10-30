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

                ZStack(alignment: .top) {
                    WebViewContainer(webViews: model.tabs.map { $0.webView }, active: model.webView)
                        .opacity(model.isHome ? 0 : 1)
                        .allowsHitTesting(!model.isHome)

                    if model.isHome {
                        HomeView(model: model)
                            .transition(.opacity)
                    } else if model.isLoading {
                        PageLoadingHUD(host: model.host, progress: model.progress)
                            .padding(.top, 13)
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .opacity))
                            .zIndex(2)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .bottom) { AppDockView(model: model) }
                .animation(.spring(response: 0.38, dampingFraction: 0.84), value: model.isHome)
                .animation(.easeInOut(duration: 0.22), value: model.isLoading)

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
