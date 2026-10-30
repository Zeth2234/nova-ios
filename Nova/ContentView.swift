import SwiftUI

struct ContentView: View {
    @StateObject private var model = BrowserModel()
    @State private var showSettings = false
    @State private var showTabs = false
    @State private var showEQ = false
    @State private var isEditingAddress = false
    @ObservedObject private var eq = EQModel.shared

    private var showsSuggestions: Bool { isEditingAddress && !model.isHome }

    var body: some View {
        ZStack {
            NovaBackground().ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                content
                if !isEditingAddress {
                    BottomBar(model: model,
                              openSettings: { showSettings = true },
                              openTabs: { showTabs = true },
                              openEQ: { showEQ = true },
                              eqOn: eq.s.enabled)
                        .background(NovaTheme.bg.opacity(0.97).ignoresSafeArea(edges: .bottom))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.88), value: isEditingAddress)
        }
        .preferredColorScheme(.dark)
        .onChange(of: model.isHome) { _ in isEditingAddress = false }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showEQ) {
            EQSheet(host: model.isHome ? "Todas las pestañas" : model.host,
                    openTest: {
                        showEQ = false
                        model.createTab()
                        model.activeTab.loadEQTestPage()
                    })
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showTabs) {
            TabSwitcherView(model: model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: Barra superior

    @ViewBuilder private var topBar: some View {
        if model.isHome {
            HomeTopBar(openSettings: { showSettings = true })
        } else {
            AddressBar(model: model, isEditing: $isEditingAddress)
                .background(NovaTheme.bg.opacity(0.97).ignoresSafeArea(edges: .top))
        }
    }

    // MARK: Contenido

    private var content: some View {
        ZStack(alignment: .top) {
            WebViewContainer(webViews: model.tabs.map { $0.webView }, active: model.webView)
                .opacity(model.isHome ? 0 : 1)
                .allowsHitTesting(!model.isHome)

            if model.isHome {
                HomeView(model: model)
                    .transition(.opacity)
            }

            if showsSuggestions {
                AddressSuggestions(model: model, isEditing: $isEditingAddress)
                    .transition(.opacity)
                    .zIndex(3)
            }
        }
        .overlay(alignment: .bottom) {
            if !isEditingAddress { AppDockView(model: model) }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.84), value: model.isHome)
    }
}
