import Foundation
import Network
import MonitorCore

/// A separate asynchronous request; never runs on the metric collector queue.
@MainActor
final class PublicIPLocationService {
    private let onChange: (PublicIPLocation?) -> Void
    private let session: URLSession
    private let pathMonitor = NWPathMonitor()
    private var request: Task<Void, Never>?
    private var generation = 0
    private var context = ""
    private var provider: PublicIPProvider?
    private var connected = false
    private var suspended = false
    private var nextAttempt = Date.distantPast

    init(onChange: @escaping (PublicIPLocation?) -> Void) {
        self.onChange = onChange
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 10
        config.waitsForConnectivity = false
        config.urlCache = nil
        config.httpShouldSetCookies = false
        session = URLSession(configuration: config)
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor in self?.pathChanged(connected: connected) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "local.SystemMonitor.public-ip-path"))
    }
    deinit {
        request?.cancel(); pathMonitor.cancel(); session.invalidateAndCancel()
    }
    private func pathChanged(connected: Bool) {
        self.connected = connected
        if !connected {
            generation += 1; request?.cancel(); request = nil
            nextAttempt = .distantPast; onChange(nil)
        } else { refresh(interface: context, provider: provider, force: true) }
    }
    func suspend(_ value: Bool) {
        guard suspended != value else { return }
        suspended = value
        generation += 1; request?.cancel(); request = nil
        if !value { refresh(interface: context, provider: provider, force: true) }
    }
    func refresh(interface: String, provider: PublicIPProvider?, force: Bool = false) {
        let changed = context != interface || self.provider != provider
        context = interface; self.provider = provider
        if force || changed {
            generation += 1; request?.cancel(); request = nil
            nextAttempt = .distantPast; onChange(nil)
        }
        guard let provider, !suspended, connected, !interface.isEmpty, request == nil, Date() >= nextAttempt else { return }
        let token = generation
        let session = session
        request = Task { [weak self] in
            let location: PublicIPLocation?
            do {
                var request = URLRequest(url: provider.endpoint)
                request.cachePolicy = .reloadIgnoringLocalCacheData
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      data.count <= 8192, let trace = String(data: data, encoding: .utf8),
                      let value = PublicIPLocation(ipipText: trace) else { throw URLError(.cannotParseResponse) }
                location = value
            } catch { location = nil }
            guard let self, !Task.isCancelled, self.generation == token else { return }
            self.request = nil
            self.nextAttempt = Date().addingTimeInterval(location == nil ? 60 : 900)
            self.onChange(location)
        }
    }
}
