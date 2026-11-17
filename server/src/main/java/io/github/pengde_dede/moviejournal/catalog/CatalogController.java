package io.github.pengde_dede.moviejournal.catalog;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

@RestController
final class CatalogController {
    private static final String PREFIX = "/api/catalog/3";
    private static final Set<String> LANGUAGES = Set.of("zh-CN", "en-US");
    private final TrialAccess access;
    private final TmdbUpstream upstream;

    CatalogController(TrialAccess access, TmdbUpstream upstream) {
        this.access = access;
        this.upstream = upstream;
    }

    record InviteRequest(String code) {}

    @GetMapping("/api/health")
    Map<String, String> health() { return Map.of("status", "ok"); }

    @PostMapping("/api/trial/session")
    ResponseEntity<TrialAccess.Session> session(@RequestBody InviteRequest invite) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(access.exchange(invite.code()));
    }

    @GetMapping({PREFIX + "/search/multi", PREFIX + "/search/person"})
    ResponseEntity<byte[]> search(@RequestHeader(value = HttpHeaders.AUTHORIZATION, required = false) String token,
                                  @RequestParam String query, jakarta.servlet.http.HttpServletRequest request) {
        access.authorize(token);
        String term = query.strip();
        if (term.isEmpty() || term.length() > 160) throw badRequest();
        String path = request.getRequestURI().endsWith("/person") ? "/3/search/person" : "/3/search/multi";
        return upstream.get(path, Map.of("query", term, "language", "zh-CN", "page", "1", "include_adult", "false"));
    }

    @GetMapping(PREFIX + "/{type:movie|tv}/{id}")
    ResponseEntity<byte[]> details(@RequestHeader(value = HttpHeaders.AUTHORIZATION, required = false) String token,
                                   @PathVariable String type, @PathVariable int id,
                                   @RequestParam(defaultValue = "zh-CN") String language,
                                   @RequestParam(name = "append_to_response", defaultValue = "") String appendix) {
        access.authorize(token);
        if (id < 1 || !LANGUAGES.contains(language)) throw badRequest();
        var query = new LinkedHashMap<String, String>();
        query.put("language", language);
        if (!appendix.isEmpty()) {
            String allowed = type.equals("movie") ? "credits,external_ids" : "aggregate_credits,external_ids";
            if (!appendix.equals(allowed)) throw badRequest();
            query.put("append_to_response", allowed);
        }
        return upstream.get("/3/" + type + "/" + id, query);
    }

    @GetMapping(PREFIX + "/movie/{id}/credits")
    ResponseEntity<byte[]> movieCredits(@RequestHeader(value = HttpHeaders.AUTHORIZATION, required = false) String token,
                                        @PathVariable int id) {
        return credits(token, id, "/3/movie/" + id + "/credits");
    }

    @GetMapping(PREFIX + "/person/{id}/combined_credits")
    ResponseEntity<byte[]> personCredits(@RequestHeader(value = HttpHeaders.AUTHORIZATION, required = false) String token,
                                         @PathVariable int id) {
        return credits(token, id, "/3/person/" + id + "/combined_credits");
    }

    private ResponseEntity<byte[]> credits(String token, int id, String path) {
        access.authorize(token);
        if (id < 1) throw badRequest();
        return upstream.get(path, Map.of("language", "zh-CN"));
    }

    private static ResponseStatusException badRequest() {
        return new ResponseStatusException(HttpStatus.BAD_REQUEST);
    }
}
