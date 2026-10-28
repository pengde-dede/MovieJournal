import Foundation
import Testing
@testable import MovieJournal

@Suite("影片接口与解析")
struct NetworkClientTests {
    @Test("中文搜索只请求第一页并过滤人物，保留同编号的不同类型")
    func searchOnlyReturnsMoviesAndSeries() async throws {
        let transport = ScriptedTransport([.json(#"{"results":[{"id":123,"media_type":"person","name":"人物"},{"id":123,"media_type":"movie","title":"电影","original_title":"Movie","release_date":"2020-01-01"},{"id":123,"media_type":"tv","name":"剧集","original_name":"Series","first_air_date":""}]}"#)])
        let results = try await TMDBClient(transport: transport).search(title: "肖申克 & 救赎", key: "fake-key")
        #expect(results.map(\.mediaType) == [.movie, .tv])
        #expect(results[0].id != results[1].id)
        #expect(results[1].releaseYear == nil)
        let requests = await transport.requests
        let request = try #require(requests.first)
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(request.httpMethod == "GET")
        #expect(url.host == "api.themoviedb.org")
        #expect(url.path == "/3/search/multi")
        #expect(query("query", components) == "肖申克 & 救赎")
        #expect(query("language", components) == "zh-CN")
        #expect(query("page", components) == "1")
        #expect(query("include_adult", components) == "false")
        #expect(query("api_key", components) == "fake-key")
    }

    @Test("电影一次合并详情、导演、前五位主演与外部编号")
    func movieDetailsUseAppendedCredits() async throws {
        let transport = ScriptedTransport([.json(try Fixtures.movieJSON())])
        let details = try await TMDBClient(transport: transport).details(for: Fixtures.movie, key: "fake")
        #expect(details.creatorNames == ["Frank Darabont"])
        #expect(details.castNames == ["演员1", "演员2", "演员3", "演员4", "演员5"])
        #expect(details.imdbID == "tt0111161")
        #expect(details.tmdbRating == 8.7)
        let requests = await transport.requests
        #expect(requests.count == 1)
        let url = try #require(requests.first?.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(query("append_to_response", components) == "credits,external_ids")
    }

    @Test("剧集使用主创与整剧演员表，IMDb 编号取外部编号")
    func seriesUsesCreatorsAndAggregateCast() async throws {
        let json = #"{"id":1396,"name":"绝命毒师","original_name":"Breaking Bad","first_air_date":"2008-01-20","overview":"中文剧集简介","created_by":[{"id":1,"name":"Vince Gilligan"}],"credits":{"cast":[{"name":"不应使用的最新季演员"}],"crew":[{"name":"分集导演","job":"Director"}]},"aggregate_credits":{"cast":[{"id":2,"name":"Bryan Cranston","order":0},{"id":3,"name":"Aaron Paul","order":1}]},"external_ids":{"imdb_id":"tt0903747"}}"#
        let transport = ScriptedTransport([.json(json)])
        let details = try await TMDBClient(transport: transport).details(for: Fixtures.series, key: "fake")
        #expect(details.creatorNames == ["Vince Gilligan"])
        #expect(details.castNames == ["Bryan Cranston", "Aaron Paul"])
        #expect(details.imdbID == "tt0903747")
        #expect(details.releaseYear == 2008)
        #expect(details.tmdbRating == nil)
        let requests = await transport.requests
        let url = try #require(requests.first?.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(query("append_to_response", components) == "aggregate_credits,external_ids")
    }

    @Test("中文简介为空时仅追加一次英文详情请求并标记英文")
    func missingChineseOverviewFallsBackToEnglish() async throws {
        let transport = ScriptedTransport([.json(try Fixtures.movieJSON(overview: " \n")), .json(#"{"id":278,"overview":"An English overview."}"#)])
        let details = try await TMDBClient(transport: transport).details(for: Fixtures.movie, key: "fake")
        #expect(details.overview == "An English overview.")
        #expect(details.overviewLanguage == "en")
        #expect(details.creatorNames == ["Frank Darabont"])
        let requests = await transport.requests
        #expect(requests.count == 2)
        let url = try #require(requests.last?.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(query("language", components) == "en-US")
        #expect(query("append_to_response", components) == nil)
    }

    @Test("英文简介请求失败仍返回可保存的影片资料")
    func englishFailureDoesNotDiscardDetails() async throws {
        let transport = ScriptedTransport([.json(try Fixtures.movieJSON(overview: "")), .failure(.networkUnavailable)])
        let details = try await TMDBClient(transport: transport).details(for: Fixtures.movie, key: "fake")
        #expect(details.overview.isEmpty)
        #expect(details.informationNote != nil)
        #expect(details.creatorNames == ["Frank Darabont"])
        #expect(details.castNames.count == 5)
    }

    @Test("没有投票时不把 TMDB 的 0 当成真实评分")
    func noVotesMeansNoRating() async throws {
        let transport = ScriptedTransport([.json(try Fixtures.movieJSON(votes: 0))])
        let details = try await TMDBClient(transport: transport).details(for: Fixtures.movie, key: "fake")
        #expect(details.tmdbRating == nil)
    }

    @Test("OMDb 按 IMDb 编号读取十分制和百分比，N/A 保持为空")
    func omdbParsesOptionalRatings() async throws {
        let transport = ScriptedTransport([
            .json(#"{"Response":"True","imdbRating":"9.3","Ratings":[{"Source":"Rotten Tomatoes","Value":"89%"}]}"#),
            .json(#"{"Response":"True","imdbRating":"N/A","Ratings":[{"Source":"Rotten Tomatoes","Value":"N/A"}]}"#)
        ])
        let client = OMDbClient(transport: transport)
        #expect(try await client.ratings(imdbID: "tt0111161", key: "fake") == PlatformRatings(imdb: 9.3, rottenTomatoes: 89))
        #expect(try await client.ratings(imdbID: "tt0903747", key: "fake") == PlatformRatings(imdb: nil, rottenTomatoes: nil))
        let requests = await transport.requests
        let url = try #require(requests.first?.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(url.scheme == "https")
        #expect(url.host == "www.omdbapi.com")
        #expect(query("i", components) == "tt0111161")
    }

    @Test("TMDB 验证调用 GET authentication；OMDb 用固定 IMDb 编号")
    func validationUsesRequestedEndpoints() async throws {
        let transport = ScriptedTransport([.json(#"{"success":true}"#), .json(#"{"Response":"True","imdbRating":"N/A"}"#)])
        let validator = APIKeyValidator(tmdb: TMDBClient(transport: transport), omdb: OMDbClient(transport: transport))
        #expect(try await validator.validate(.tmdb, key: "fake-tmdb") == .valid)
        #expect(try await validator.validate(.omdb, key: "fake-omdb") == .valid)
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests[0].httpMethod == "GET")
        #expect(requests[0].url?.path == "/3/authentication")
        let url = try #require(requests[1].url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(query("i", components) == "tt0111161")
    }

    @Test("无效 Key 与网络失败分别报告")
    func validationDistinguishesInvalidKeyFromNetwork() async throws {
        let transport = ScriptedTransport([.json("{}", status: 401), .json(#"{"Response":"False","Error":"Invalid API key!"}"#), .failure(.networkUnavailable)])
        let validator = APIKeyValidator(tmdb: TMDBClient(transport: transport), omdb: OMDbClient(transport: transport))
        #expect(try await validator.validate(.tmdb, key: "fake") == .invalid)
        #expect(try await validator.validate(.omdb, key: "fake") == .invalid)
        let result = try await validator.validate(.tmdb, key: "fake")
        if case .networkFailure = result {} else { Issue.record("网络故障不能报告为 Key 无效") }
    }

    @Test("服务限流或故障不错误判断 Key 无效", arguments: [429, 500])
    func serviceFailureDoesNotInvalidateKey(status: Int) async throws {
        let transport = ScriptedTransport([.json("{}", status: status)])
        let validator = APIKeyValidator(tmdb: TMDBClient(transport: transport))
        let result = try await validator.validate(.tmdb, key: "fake")
        if case .unavailable = result {} else { Issue.record("服务失败应提示暂时无法验证") }
    }

    @Test("缺少 Key 不发请求，OMDb 未配置不影响主数据")
    func missingKeysDoNotMakeRequests() async throws {
        let transport = ScriptedTransport([])
        let catalog = MediaCatalogService(keychain: MemoryKeychain(), tmdb: TMDBClient(transport: transport), omdb: OMDbClient(transport: transport))
        await #expect(throws: APIError.missingKey(.tmdb)) { try await catalog.search(title: "电影") }
        #expect(try await catalog.supplementalRatings(imdbID: "tt0111161") == .notConfigured)
        #expect(try await catalog.supplementalRatings(imdbID: nil) == .noIMDbID)
        #expect(await transport.requests.isEmpty)
    }

    @Test("人物搜索只请求第一页，导演排在前面且各自保留相关度顺序")
    func peopleSearchPutsDirectorsFirst() async throws {
        let json = #"""
        {"results":[
          {"id":1,"name":"诺兰·诺斯","known_for_department":"Acting","profile_path":"/north.jpg","known_for":[{"id":10,"media_type":"tv","name":"少年正义联盟"},{"id":11,"media_type":"movie","title":"神秘海域"}]},
          {"id":525,"name":"克里斯托弗·诺兰","known_for_department":"Directing","profile_path":"/nolan.jpg","known_for":[{"id":157336,"media_type":"movie","title":"星际穿越"},{"id":27205,"media_type":"movie","title":"盗梦空间"},{"id":155,"media_type":"movie","title":"蝙蝠侠：黑暗骑士"},{"id":12,"media_type":"movie","title":"第四部"}]},
          {"id":2,"name":"  ","known_for_department":"Directing"},
          {"id":3,"name":"肯·诺兰","known_for_department":"Writing","known_for":[]},
          {"id":4,"name":"阿兰·科尔诺","known_for_department":"Directing"}
        ]}
        """#
        let transport = ScriptedTransport([.json(json)])
        let people = try await TMDBClient(transport: transport).searchPeople(name: "诺兰", key: "fake-key")
        #expect(people.map(\.id) == [525, 4, 1, 3])
        #expect(people[0].knownFor == ["星际穿越", "盗梦空间", "蝙蝠侠：黑暗骑士"])
        #expect(people[0].departmentTitle == "导演")
        #expect(people[0].profilePath == "/nolan.jpg")
        #expect(people[2].knownFor == ["少年正义联盟", "神秘海域"])
        #expect(people[2].departmentTitle == "演员")
        #expect(people[3].knownFor.isEmpty)
        let url = try #require(await transport.requests.first?.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(url.path == "/3/search/person")
        #expect(query("query", components) == "诺兰")
        #expect(query("language", components) == "zh-CN")
        #expect(query("page", components) == "1")
        #expect(query("include_adult", components) == "false")
        #expect(query("api_key", components) == "fake-key")
    }

    @Test("人物作品只保留执导的电影和主创的剧集，去重后从新到旧排列")
    func directedWorksFiltersSortsAndDeduplicates() async throws {
        let json = #"""
        {"cast":[{"id":900,"media_type":"movie","title":"客串电影","release_date":"2024-01-01"}],
         "crew":[
          {"id":1,"media_type":"movie","title":"老片","original_title":"Old","release_date":"1998-04-24","job":"Director","department":"Directing","poster_path":"/old.jpg"},
          {"id":2,"media_type":"movie","title":"新片","original_title":"New","release_date":"2023-07-19","job":"Director","department":"Directing"},
          {"id":2,"media_type":"movie","title":"新片","original_title":"New","release_date":"2023-07-19","job":"Director","department":"Directing"},
          {"id":2,"media_type":"movie","title":"新片","release_date":"2023-07-19","job":"Writer","department":"Writing"},
          {"id":3,"media_type":"movie","title":"只做编剧","release_date":"2010-01-01","job":"Screenplay","department":"Writing"},
          {"id":4,"media_type":"movie","title":"","original_title":"Untitled Project","release_date":"","job":"Director","department":"Directing"},
          {"id":1396,"media_type":"tv","name":"绝命毒师","original_name":"Breaking Bad","first_air_date":"2008-01-20","job":"Creator","department":"Creator"},
          {"id":1396,"media_type":"tv","name":"绝命毒师","first_air_date":"2008-01-20","job":"Director","department":"Directing"},
          {"id":5,"media_type":"tv","name":"只导过单集","first_air_date":"2015-01-01","job":"Director","department":"Directing"},
          {"id":2,"media_type":"tv","name":"同编号剧集","first_air_date":"2001-01-01","job":"Creator","department":"Creator"}
         ]}
        """#
        let transport = ScriptedTransport([.json(json)])
        let works = try await TMDBClient(transport: transport).directedWorks(personID: 525, key: "fake-key")
        #expect(works.map(\.id) == ["movie:2", "tv:1396", "tv:2", "movie:1", "movie:4"])
        #expect(works.map(\.role) == [.director, .creator, .creator, .director, .director])
        #expect(works[0].result.releaseYear == 2023)
        #expect(works[1].result.originalTitle == "Breaking Bad")
        #expect(works[3].result.posterPath == "/old.jpg")
        #expect(works[4].result.title == "Untitled Project")
        #expect(works[4].result.releaseYear == nil)
        let url = try #require(await transport.requests.first?.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(url.path == "/3/person/525/combined_credits")
        #expect(query("language", components) == "zh-CN")
    }

    @Test("按导演搜索同样需要 TMDB Key，缺少时不发请求")
    func peopleSearchRequiresKey() async throws {
        let transport = ScriptedTransport([])
        let catalog = MediaCatalogService(keychain: MemoryKeychain(), tmdb: TMDBClient(transport: transport))
        await #expect(throws: APIError.missingKey(.tmdb)) { try await catalog.searchPeople(name: "诺兰") }
        await #expect(throws: APIError.missingKey(.tmdb)) { try await catalog.directedWorks(personID: 525) }
        #expect(await transport.requests.isEmpty)
    }

    private func query(_ key: String, _ components: URLComponents) -> String? {
        components.queryItems?.first { $0.name == key }?.value
    }
}
