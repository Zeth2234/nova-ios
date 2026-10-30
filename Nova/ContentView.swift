import SwiftUI

struct ContentView: View {
    @StateObject private var model = BrowserModel()
    @State private var showSettings = false

    var body: some View {
        ZStack {
            NovaBackground().ignoresSafeArea()

            VStack(spacing: 0) {
                if model.isHome {
                    HomeTopBar(openSettings: { showSettings = true })
                } else {
                    AddressBar(model: model)
                        .background(NovaTheme.bg.ignoresSafeArea(edges: .top))
                }

                ZStack {
                    WebViewContainer(webView: model.webView)
                        .opacity(model.isHome ? 0 : 1)
                        .allowsHitTesting(!model.isHome)
                    if model.isHome {
                        HomeView(model: model)
                    }
                }

                BottomBar(model: model, openSettings: { showSettings = true })
                    .background(
                        (model.isHome ? Color.clear : NovaTheme.bg)
                            .ignoresSafeArea(edges: .bottom)
                    )
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(NovaTheme.stroke)
                            .frame(height: model.isHome ? 0 : 1)
                    }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .presentationDragIndicator(.visible)
        }
    }
}
