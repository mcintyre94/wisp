import SwiftUI

struct ServicesView: View {
    let spriteName: String
    var viewModel: ServicesViewModel
    @Environment(SpritesAPIClient.self) private var apiClient
    @State private var serviceToStop: ServiceInfo?

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.services.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.services.isEmpty {
                ContentUnavailableView(
                    "No Services",
                    systemImage: "gearshape.2",
                    description: Text("No running services on this sprite.")
                )
            } else {
                List(viewModel.services) { service in
                    let name = viewModel.displayName(for: service)
                    NavigationLink(value: service) {
                        ServiceRowView(service: service, displayName: name)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            serviceToStop = service
                        } label: {
                            Label("Stop", systemImage: "stop.circle")
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            serviceToStop = service
                        } label: {
                            Label("Stop", systemImage: "stop.circle")
                        }
                    }
                }
            }
        }
        .navigationTitle("Services")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.refresh(apiClient: apiClient)
        }
        .navigationDestination(for: ServiceInfo.self) { service in
            ServiceDetailView(
                spriteName: spriteName,
                service: service,
                displayName: viewModel.displayName(for: service)
            )
        }
        .confirmationDialog(
            stopDialogTitle,
            isPresented: Binding(
                get: { serviceToStop != nil },
                set: { if !$0 { serviceToStop = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Stop Service", role: .destructive) {
                if let service = serviceToStop {
                    Task { await viewModel.stop(service: service, apiClient: apiClient) }
                    serviceToStop = nil
                }
            }
        } message: {
            Text("This will terminate the service process.")
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            if let msg = viewModel.errorMessage { Text(msg) }
        }
    }

    private var stopDialogTitle: String {
        if let service = serviceToStop {
            return "Stop \"\(viewModel.displayName(for: service))\"?"
        }
        return "Stop Service?"
    }
}

#Preview {
    let vm = ServicesViewModel(spriteName: "my-sprite")
    vm.services = [
        ServiceInfo(
            name: "wisp-claude-abc123",
            cmd: "claude",
            args: ["-p"],
            httpPort: nil,
            needs: [],
            state: ServiceInfo.ServiceState(name: "wisp-claude-abc123", pid: 1234, startedAt: Date(), status: "running")
        ),
        ServiceInfo(
            name: "webapp",
            cmd: "python",
            args: ["-m", "http.server", "8000"],
            httpPort: 8000,
            needs: [],
            state: ServiceInfo.ServiceState(name: "webapp", pid: 1567, startedAt: Date(), status: "running")
        )
    ]
    vm.displayNames = ["wisp-claude-abc123": "Chat 1"]

    return NavigationStack {
        ServicesView(spriteName: "my-sprite", viewModel: vm)
            .environment(SpritesAPIClient())
    }
}
