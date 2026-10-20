import { useState, type FormEvent } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Link, Navigate, useNavigate } from "react-router";
import { api, ApiError } from "../api";
import { useMe } from "../session";
import { Logo } from "../components/Logo";
import type { Me } from "../types";

const UNREACHABLE = "Couldn't reach Cubby. Check your connection and try again.";

export function SignIn() {
  const me = useMe();
  const client = useQueryClient();
  const navigate = useNavigate();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState<"password" | "demo" | null>(null);
  // A 404 means this deployment has no demo; the form is all there is.
  const demo = useQuery({ queryKey: ["demo"], queryFn: api.demo, retry: false, staleTime: Infinity });

  if (me.data) return <Navigate to="/inbox" replace />;
  // Wait for the demo check so the page doesn't change shape (or steal focus) a moment after it appears.
  if (demo.isPending) return <div className="splash" aria-busy="true"><Logo /></div>;

  const enter = async (kind: "password" | "demo", signIn: () => Promise<Me>) => {
    setPending(kind);
    setError(null);
    try {
      client.setQueryData(["me"], await signIn());
      navigate("/inbox", { replace: true });
    } catch (err) {
      setError(err instanceof ApiError ? err.message : UNREACHABLE);
      setPending(null);
    }
  };

  const submit = (e: FormEvent) => {
    e.preventDefault();
    void enter("password", () => api.signIn(email, password));
  };

  const offline = demo.error instanceof ApiError && demo.error.status === 503;

  // The public demo has nothing to sign in to, so it offers the two sides of Cubby instead of a form.
  if (demo.data) {
    return (
      <main className="signin">
        <div className="signin__card signin__card--roles">
          <Logo />
          <section className="roles" aria-labelledby="roles-title">
            <div className="roles__intro">
              <h1 id="roles-title">Try Cubby</h1>
              <p className="muted">
                A daily queue for preschool directors: waitlist families to call, tuition to chase, and rooms that need
                covering. Pick a side to look around.
              </p>
            </div>
            <div className="roles__grid">
              <article className="role">
                <span className="role__kicker">Director</span>
                <h2>{demo.data.director_name}</h2>
                <p className="role__where">{demo.data.center_name ?? "A demo center"}</p>
                <p className="muted">
                  Work the live queue: approve or edit what Cubby found, and see what happened after.
                </p>
                <button
                  type="button"
                  className="button button--primary button--block"
                  disabled={pending !== null}
                  onClick={() => void enter("demo", api.signInToDemo)}
                >
                  {pending === "demo" ? "Opening the inbox…" : "Open the director inbox"}
                </button>
              </article>
              <article className="role">
                <span className="role__kicker">Parent</span>
                <h2>The Russel family</h2>
                <p className="role__where">iPhone and Android</p>
                <p className="muted">
                  Check-ins, notes the director approved, and tuition, in the parent apps on the same API.
                </p>
                <Link className="button button--quiet button--block" to="/apps">
                  See the parent apps
                </Link>
              </article>
            </div>
            {error && <p className="form-error" role="alert">{error}</p>}
            <p className="demo__note">Everything here is fictional and resets every night.</p>
          </section>
        </div>
      </main>
    );
  }

  return (
    <main className="signin">
      <div className="signin__card">
        <Logo />
        <h1>Sign in</h1>
        <p className="muted">Your center's daily queue: who to follow up with, and what needs covering.</p>
        {offline && (
          <p className="form-error" role="status">
            The demo is offline right now. Try again later.
          </p>
        )}
        {error && <p className="form-error" role="alert">{error}</p>}
        <form onSubmit={submit} noValidate>
          <label className="field">
            <span className="field__label">Email</span>
            <input
              className="field__input"
              type="email"
              autoComplete="username"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              autoFocus
            />
          </label>
          <label className="field">
            <span className="field__label">Password</span>
            <input
              className="field__input"
              type="password"
              autoComplete="current-password"
              required
              value={password}
              onChange={(e) => setPassword(e.target.value)}
            />
          </label>
          <button
            className="button button--primary button--block"
            type="submit"
            disabled={pending !== null || !email || !password}
          >
            {pending === "password" ? "Signing in…" : "Sign in"}
          </button>
        </form>
      </div>
    </main>
  );
}
