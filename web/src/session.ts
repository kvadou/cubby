import { useQuery } from "@tanstack/react-query";
import { api, ApiError } from "./api";
import type { Me } from "./types";

// null means "signed out"; a 401 is an answer, not an error.
export function useMe() {
  return useQuery<Me | null>({
    queryKey: ["me"],
    queryFn: async () => {
      try {
        return await api.me();
      } catch (e) {
        if (e instanceof ApiError && e.status === 401) return null;
        throw e;
      }
    },
    staleTime: 5 * 60_000,
  });
}
