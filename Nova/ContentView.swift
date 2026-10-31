import SwiftUI

struct ContentView: View {
    @StateObject private var model = BrowserModel()
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var privacy = PrivacyStore.shared
    @ObservedObject private var eq = EQModel.shared
    @ObservedObject private var login = QuickLogin.shared
    @ObservedObject private var panel = PanelStore.shared
    @ObservedObject private var account = NovaAccount.shared
    @ObservedObject private var link = NovaLink.shared
    @State private var showAccount = false
    @State private var showSettings = false
    @State private var showTabs = false
    @State private var showEQ = false
    @State private var isEditingAddress = false
    @State private var cameFromBackground = false

    private var showsSuggestions: Bool { isEditingAddress && !model.isHome }
    private var barBackground: Color { model.isPrivate ? PrivateTheme.bg : NovaTheme.bg }

    /// Tapa la pantalla cuando Nova no está en primer plano (selector de apps).
    private var shieldVisible: Bool {
        scenePhase != .active && (privacy.lockApp || model.activeTab.isPrivate)
    }

    var body: some View {
        ZStack {
            if model.isPrivate {
                PrivateBackground().ignoresSafeArea()
            } else {
                NovaBackground().ignoresSafeArea()
            }

            ZStack {
                if model.isHome && !model.isPrivate {
                    HomeBackgroundView()
                        .ignoresSafeArea()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: model.isHome)

            VStack(spacing: 0) {
                topBar
                content
                if !isEditingAddress {
                    BottomBar(model: model,
                              openSettings: { showSettings = true },
                              openTabs: { showTabs = true },
                              openEQ: { showEQ = true },
                              eqOn: eq.s.enabled,
                              openPanel: { panel.setOpen(true) },
                              openAccount: { showAccount = true },
                              newPrivateTab: {
                                  privacy.requestPrivateAccess { ok in
                                      if ok { model.createTab(private: true) }
                                  }
                              })
                        .background((model.isHome ? Color.clear : barBackground.opacity(0.97)).ignoresSafeArea(edges: .bottom))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.88), value: isEditingAddress)

            // Panel de apps (lateral, por encima de todo).
            if panel.isOpen {
                Color.black.opacity(0.38)
                    .ignoresSafeArea()
                    .onTapGesture { panel.setOpen(false) }
                    .transition(.opacity)
                    .zIndex(5)
                AppSidePanel(model: model)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .zIndex(6)
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: panel.isOpen)
        .overlay {
            if privacy.isLocked {
                LockScreenView().transition(.opacity)
            }
        }
        .overlay {
            if shieldVisible { PrivacyShield() }
        }
        .animation(.easeInOut(duration: 0.2), value: privacy.isLocked)
        .novaAppearance()
        .onChange(of: model.isHome) { _ in isEditingAddress = false }
        .onChange(of: isEditingAddress) { editing in if editing { panel.setOpen(false) } }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .background:
                privacy.enteredBackground(activeIsPrivate: model.activeTab.isPrivate)
                cameFromBackground = true
                account.appWentBackground()
                link.appWentBackground()
            case .active:
                if cameFromBackground {
                    cameFromBackground = false
                    privacy.unlock()
                    account.appBecameActive()
                    link.appBecameActive()
                }
            default:
                break
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { privacy.unlock() }
            link.model = model
            link.connectIfNeeded()
        }
        .onChange(of: account.phase) { phase in if phase == .signedIn { link.connectIfNeeded(force: true) } }
        .overlay(alignment: .bottom) {
            if !link.showDevices { NovaLinkToast().padding(.bottom, 60) }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: link.toast)
        // v88 · Dispositivos: emparejar con el PC, Puente móvil, Transferencias y archivos.
        .sheet(isPresented: $link.showDevices) {
            NovaDevicesView(model: model)
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $link.pcPick) { req in
            PCPickSheet(request: req)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showAccount) {
            AccountHubView()
                .presentationDragIndicator(.visible)
        }
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
            if model.isPrivate {
                PrivateTopBar(openSettings: { showSettings = true })
            } else {
                HomeTopBar(openSettings: { showSettings = true }, openAccount: { showAccount = true })
            }
        } else {
            AddressBar(model: model, isEditing: $isEditingAddress)
                .background(barBackground.opacity(0.97).ignoresSafeArea(edges: .top))
        }
    }

    // MARK: Contenido

    private var content: some View {
        ZStack(alignment: .top) {
            WebViewContainer(webViews: model.tabs.map { $0.webView }, active: model.webView)
                .opacity(model.isHome ? 0 : 1)
                .allowsHitTesting(!model.isHome)

            if model.isHome {
                if model.isPrivate {
                    PrivateHomeView(model: model)
                        .transition(.opacity)
                } else {
                    HomeView(model: model)
                        .transition(.opacity)
                }
            }

            if !model.isHome && !isEditingAddress {
                VStack(alignment: .trailing, spacing: 8) {
                    QuickToastView()
                    SavePasswordCard(model: model)
                    QuickLoginPill(model: model)
                }
                .padding(.top, 8)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .animation(.spring(response: 0.36, dampingFraction: 0.86), value: login.offer)
                .animation(.spring(response: 0.36, dampingFraction: 0.86), value: login.toast)
                .animation(.spring(response: 0.36, dampingFraction: 0.86), value: login.savePrompt != nil)
                .zIndex(2)
            }

            if showsSuggestions {
                AddressSuggestions(model: model, isEditing: $isEditingAddress)
                    .transition(.opacity)
                    .zIndex(3)
            }
        }
        .overlay(alignment: .bottom) {
            if !isEditingAddress { PanelBottomOverlay(model: model) }
        }
        .overlay(alignment: .leading) {
            if !isEditingAddress { PanelEdgeHandle(model: model).offset(y: 40) }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.84), value: model.isHome)
    }
}
