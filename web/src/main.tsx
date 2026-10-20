import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { QueryCache, QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter } from "react-router";
import { ApiError } from "./api";
import { App } from "./App";
import { ToastProvider } from "./components/Toasts";
import "./styles.css";

const client: QueryClient = new QueryClient({
  // An expired or revoked session on any request sends the director back to sign in.
  queryCache: new QueryCache({
    onError: (err) => {
      if (err instanceof ApiError && err.status === 401) client.setQueryData(["me"], null);
    },
  }),
  defaultOptions: {
    queries: {
      // A 4xx will not fix itself on retry, and neither will the deployed demo being switched off.
      retry: (count, err) =>
        !(err instanceof ApiError && (err.status < 500 || err.body.error === "offline")) && count < 2,
      refetchOnWindowFocus: true,
    },
  },
});

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <QueryClientProvider client={client}>
      <BrowserRouter>
        <ToastProvider>
          <App />
        </ToastProvider>
      </BrowserRouter>
    </QueryClientProvider>
  </StrictMode>,
);
