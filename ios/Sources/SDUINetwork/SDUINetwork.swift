import Foundation
import SDUICore

/// Maps a logical `service` name from the contract to a concrete base URL and
/// per-request headers (auth, tracing). Payloads never hardcode hostnames — the
/// host app owns this mapping, so the same JSON runs against staging or prod
/// unchanged.
public protocol ServiceResolver: Sendable {
    func baseURL(for service: String) -> URL?
    func defaultHeaders(for service: String) -> [String: String]
}

public struct StaticServiceResolver: ServiceResolver {
    private let services: [String: URL]
    private let headers: [String: [String: String]]

    public init(services: [String: URL], headers: [String: [String: String]] = [:]) {
        self.services = services
        self.headers = headers
    }
    public func baseURL(for service: String) -> URL? { services[service] }
    public func defaultHeaders(for service: String) -> [String: String] { headers[service] ?? [:] }
}

public enum SDUINetworkError: Error, CustomStringConvertible {
    case unknownService(String)
    case badURL(String)
    case http(status: Int, body: Data)
    case transport(Error)

    public var description: String {
        switch self {
        case .unknownService(let s): return "Unknown service '\(s)'. Register it in the ServiceResolver."
        case .badURL(let p): return "Could not build a URL for path '\(p)'."
        case .http(let status, _): return "HTTP \(status)."
        case .transport(let e): return "Transport error: \(e)"
        }
    }
}

/// Builds a `URLRequest` from a declarative `DataSource`, resolving path params,
/// query items, headers and body against the current binding context.
public struct RequestBuilder: Sendable {
    let resolver: ServiceResolver

    public init(resolver: ServiceResolver) { self.resolver = resolver }

    public func build(_ source: DataSource, ctx: BindingContext) throws -> URLRequest {
        guard let base = resolver.baseURL(for: source.service) else {
            throw SDUINetworkError.unknownService(source.service)
        }
        // Resolve `$` bindings in the path, then fill `{param}` placeholders.
        let boundPath = BindingEngine.resolveString(source.path, in: ctx)
        let resolvedPath = BindingEngine.fillPlaceholders(boundPath, in: ctx)
        guard var components = URLComponents(
            url: base.appendingPathComponent(stripLeadingSlash(resolvedPath)),
            resolvingAgainstBaseURL: false) else {
            throw SDUINetworkError.badURL(resolvedPath)
        }
        if let query = source.query, !query.isEmpty {
            components.queryItems = query
                .map { URLQueryItem(name: $0.key, value: BindingEngine.resolveString($0.value, in: ctx)) }
                .sorted { $0.name < $1.name }
        }
        guard let url = components.url else { throw SDUINetworkError.badURL(resolvedPath) }

        var request = URLRequest(url: url)
        // Fail fast rather than hang on a stalled connection — the async
        // component then shows its error slot instead of an endless skeleton.
        request.timeoutInterval = 20
        request.httpMethod = (source.method ?? .GET).rawValue
        for (k, v) in resolver.defaultHeaders(for: source.service) {
            request.setValue(v, forHTTPHeaderField: k)
        }
        for (k, v) in source.headers ?? [:] {
            request.setValue(BindingEngine.resolveString(v, in: ctx), forHTTPHeaderField: k)
        }
        if let body = source.body, !body.isNull {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        return request
    }

    private func stripLeadingSlash(_ s: String) -> String {
        s.hasPrefix("/") ? String(s.dropFirst()) : s
    }
}

/// Executes a screen's `DataConfig`, honouring `parallel` vs `sequential` mode
/// and `dependsOn` ordering. Results are returned keyed by source id, ready to
/// drop into `BindingContext.data`.
///
/// Parallel mode uses a `TaskGroup` so all independent requests run concurrently
/// and cancellation propagates cleanly — no leaked tasks when a screen goes away.
public struct DataLoader: Sendable {
    let builder: RequestBuilder
    let session: URLSession

    public init(resolver: ServiceResolver, session: URLSession = .shared) {
        self.builder = RequestBuilder(resolver: resolver)
        self.session = session
    }

    public func load(_ config: DataConfig, ctx: BindingContext) async -> [String: JSONValue] {
        let hasDependencies = config.sources.contains { !($0.dependsOn?.isEmpty ?? true) }
        if config.mode == .sequential || hasDependencies {
            return await loadSequential(config.sources, ctx: ctx)
        }
        return await loadParallel(config.sources, ctx: ctx)
    }

    private func loadParallel(_ sources: [DataSource], ctx: BindingContext) async -> [String: JSONValue] {
        await withTaskGroup(of: (String, JSONValue).self) { group in
            for source in sources {
                group.addTask { (source.id, await self.fetchOne(source, ctx: ctx)) }
            }
            var out: [String: JSONValue] = [:]
            for await (id, value) in group { out[id] = value }
            return out
        }
    }

    private func loadSequential(_ sources: [DataSource], ctx baseCtx: BindingContext) async -> [String: JSONValue] {
        // Feed each result back into the context so later sources can bind to
        // earlier ones (dependsOn). Ordering respects dependencies.
        var ctx = baseCtx
        var out: [String: JSONValue] = [:]
        for source in topologicallySorted(sources) {
            let value = await fetchOne(source, ctx: ctx)
            out[source.id] = value
            ctx.data[source.id] = value
        }
        return out
    }

    private func fetchOne(_ source: DataSource, ctx: BindingContext) async -> JSONValue {
        do {
            let request = try builder.build(source, ctx: ctx)
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return .null
            }
            return (try? JSONDecoder().decode(JSONValue.self, from: data)) ?? .null
        } catch {
            return .null
        }
    }

    /// Simple dependency-respecting order. Sources with unmet deps go later.
    private func topologicallySorted(_ sources: [DataSource]) -> [DataSource] {
        var resolved: Set<String> = []
        var result: [DataSource] = []
        var remaining = sources
        while !remaining.isEmpty {
            let ready = remaining.filter { ($0.dependsOn ?? []).allSatisfy(resolved.contains) }
            if ready.isEmpty {  // cycle or missing dep — fall back to declared order
                result.append(contentsOf: remaining)
                break
            }
            for s in ready { resolved.insert(s.id) }
            result.append(contentsOf: ready)
            remaining.removeAll { r in ready.contains { $0.id == r.id } }
        }
        return result
    }
}
