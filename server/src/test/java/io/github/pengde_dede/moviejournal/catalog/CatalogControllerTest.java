package io.github.pengde_dede.moviejournal.catalog;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.ResponseEntity;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.web.server.ResponseStatusException;

import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest(properties = {
    "MOVIEJOURNAL_TRIAL_SECRET=test-only-signing-secret-32-characters",
    "MOVIEJOURNAL_TRIAL_INVITES=local-invite-only-0001"
})
@AutoConfigureMockMvc
class CatalogControllerTest {
    @Autowired MockMvc mvc;
    @Autowired ObjectMapper json;
    @MockitoBean TmdbUpstream upstream;

    @Test void unauthenticatedRequestsDoNotReachTmdb() throws Exception {
        mvc.perform(get("/api/catalog/3/search/multi").param("query", "沙丘"))
            .andExpect(status().isUnauthorized());
        mvc.perform(post("/api/trial/session").contentType("application/json")
            .content("{\"code\":\"other-invite-only-0001\"}"))
            .andExpect(status().isUnauthorized());
        verifyNoInteractions(upstream);
    }

    @Test void anInvitedClientCanSearchAndFetchDetails() throws Exception {
        String token = token();
        var query = Map.of("query", "沙丘", "page", "1", "include_adult", "false", "language", "zh-CN");
        when(upstream.get("/3/search/multi", query)).thenReturn(ResponseEntity.ok(new byte[]{'{', '}'}));
        when(upstream.get("/3/movie/438631", Map.of("language", "zh-CN", "append_to_response", "credits,external_ids")))
            .thenReturn(ResponseEntity.ok(new byte[]{'{', '}'}));
        mvc.perform(get("/api/catalog/3/search/multi").param("query", "沙丘").param("include_adult", "true")
            .header("Authorization", "Bearer " + token)).andExpect(status().isOk()).andExpect(content().string("{}"));
        mvc.perform(get("/api/catalog/3/movie/438631").param("append_to_response", "credits,external_ids")
            .header("Authorization", "Bearer " + token)).andExpect(status().isOk());
    }

    @Test void clientCannotForwardArbitraryRoutesOrAppendedResources() throws Exception {
        String token = token();
        mvc.perform(get("/api/catalog/3/account/99").header("Authorization", "Bearer " + token))
            .andExpect(status().isNotFound());
        mvc.perform(get("/api/catalog/3/movie/42").param("append_to_response", "account_states")
            .header("Authorization", "Bearer " + token)).andExpect(status().isBadRequest());
        verifyNoInteractions(upstream);
    }

    @Test void tokensExpireAndRemovingAnInviteRevokesItsSessions() {
        var moment = Clock.fixed(Instant.parse("2026-11-17T00:00:00Z"), ZoneOffset.UTC);
        String secret = "test-only-signing-secret-32-characters";
        String invite = "local-invite-only-0001";
        String authorization = "Bearer " + new TrialAccess(secret, invite, moment).exchange(invite).token();
        var later = Clock.fixed(Instant.parse("2026-11-24T00:00:00Z"), ZoneOffset.UTC);
        assertThrows(ResponseStatusException.class, () -> new TrialAccess(secret, invite, later).authorize(authorization));
        assertThrows(ResponseStatusException.class, () -> new TrialAccess(secret, "local-invite-only-0002", moment).authorize(authorization));
    }

    private String token() throws Exception {
        var response = mvc.perform(post("/api/trial/session").contentType("application/json")
            .content("{\"code\":\"local-invite-only-0001\"}"))
            .andExpect(status().isOk()).andExpect(header().string("Cache-Control", "no-store"))
            .andReturn().getResponse();
        return json.readTree(response.getContentAsString()).get("token").asText();
    }
}
