import Foundation

struct GitHubRepo: Identifiable, Hashable, Sendable {
    let id: Int
    let fullName: String
    let description: String?
    let cloneURL: String
    let isPrivate: Bool

    var repoName: String {
        fullName.components(separatedBy: "/").last ?? fullName
    }
}

struct GitHubAPIClient: Sendable {
    let token: String?

    func fetchUserRepos() async throws -> [GitHubRepo] {
        guard token != nil else { return [] }
        let url = URL(string: "https://api.github.com/user/repos?sort=pushed&per_page=20")!
        let data = try await performRequest(url: url)
        return try decodeRepos(from: data)
    }

    func searchRepos(query: String) async throws -> [GitHubRepo] {
        guard var components = URLComponents(string: "https://api.github.com/search/repositories") else {
            return []
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "per_page", value: "20"),
        ]
        guard let url = components.url else { return [] }
        let data = try await performRequest(url: url)
        return try decodeSearchResults(from: data)
    }

    // MARK: - Private

    private func performRequest(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func decodeRepos(from data: Data) throws -> [GitHubRepo] {
        let items = try JSONDecoder().decode([RepoJSON].self, from: data)
        return items.map(\.toGitHubRepo)
    }

    private func decodeSearchResults(from data: Data) throws -> [GitHubRepo] {
        let result = try JSONDecoder().decode(SearchResultJSON.self, from: data)
        return result.items.map(\.toGitHubRepo)
    }
}

// MARK: - JSON Decoding

private struct RepoJSON: Decodable {
    let id: Int
    let fullName: String
    let description: String?
    let cloneUrl: String
    let `private`: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case description
        case cloneUrl = "clone_url"
        case `private`
    }

    var toGitHubRepo: GitHubRepo {
        GitHubRepo(id: id, fullName: fullName, description: description, cloneURL: cloneUrl, isPrivate: self.private)
    }
}

private struct SearchResultJSON: Decodable {
    let items: [RepoJSON]
}
