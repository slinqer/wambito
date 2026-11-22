import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useApi } from "../../api/ApiProvider.tsx";
import { ApiProblem } from "../../api/errors.ts";
import type { components } from "../../api/schema";

/** One assistant the person let in (`GET /v1/me/assistants`). */
export type Assistant = components["schemas"]["Assistant"];

const ASSISTANTS_KEY = ["assistants"] as const;

/** The connected assistants, newest first. Off in the demo, which has no account behind it. */
export function useAssistants({ enabled = true }: { enabled?: boolean } = {}) {
  const api = useApi();
  return useQuery({
    queryKey: ASSISTANTS_KEY,
    queryFn: async () => {
      const { data, response } = await api.GET("/v1/me/assistants");
      if (!data) throw new ApiProblem({ status: response.status, code: "internal_error" });
      return data.items;
    },
    enabled,
  });
}

/**
 * Revokes these (all of one app's grants): the API deletes its consent and tokens, so it loses access within minutes. Then
 * the list is read again. A 404 (already gone, say from another device) counts as done.
 */
export function useRevokeAssistant() {
  const api = useApi();
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (clientIds: string[]) => {
      await Promise.all(
        clientIds.map(async (clientId) => {
          try {
            await api.DELETE("/v1/me/assistants/{clientId}", { params: { path: { clientId } } });
          } catch (problem) {
            if (problem instanceof ApiProblem && problem.status === 404) return;
            throw problem;
          }
        }),
      );
    },
    onSettled: () => qc.invalidateQueries({ queryKey: ASSISTANTS_KEY }),
  });
}
