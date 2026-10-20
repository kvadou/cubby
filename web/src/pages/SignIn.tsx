import { useState, type FormEvent } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { Navigate, useNavigate } from "react-router";
import { api, ApiError } from "../api";
import { useMe } from "../session";
import { Logo } from "../components/Logo";

export function SignIn() {
  const me = useMe();
  const client = useQueryClient();
  const navigate = useNavigate();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  if (me.data) return <Navigate to="/inbox" replace />;

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    setPending(true);
    setError(null);
    try {
      client.setQueryData(["me"], await api.signIn(email, password));
      navigate("/inbox", { replace: true });
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Couldn't reach Cubby. Check your connection and try again.");
      setPending(false);
    }
  };

  return (
    <main className="signin">
      <div className="signin__card">
        <Logo />
        <h1>Sign in</h1>
        <p className="muted">Your center's daily queue: who to follow up with, and what needs covering.</p>
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
          {error && <p className="form-error" role="alert">{error}</p>}
          <button className="button button--primary button--block" type="submit" disabled={pending || !email || !password}>
            {pending ? "Signing in…" : "Sign in"}
          </button>
        </form>
        {import.meta.env.DEV && (
          <button
            type="button"
            className="button button--link"
            onClick={() => {
              setEmail("renee@littleoaks.test");
              setPassword("littleoaks-demo");
            }}
          >
            Fill in the local demo director
          </button>
        )}
      </div>
    </main>
  );
}
