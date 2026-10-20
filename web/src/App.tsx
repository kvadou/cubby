import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Navigate, NavLink, Route, Routes, useNavigate } from "react-router";
import { api } from "./api";
import { AskPanel } from "./components/AskPanel";
import { Logo } from "./components/Logo";
import { useToast } from "./components/Toasts";
import { Queue } from "./pages/Queue";
import { SignIn } from "./pages/SignIn";
import { useMe } from "./session";
import type { ListName, Me } from "./types";

export function App() {
  return (
    <Routes>
      <Route path="/sign-in" element={<SignIn />} />
      <Route path="/inbox" element={<Signed list="inbox" />} />
      <Route path="/approved" element={<Signed list="approved" />} />
      <Route path="/dismissed" element={<Signed list="dismissed" />} />
      <Route path="*" element={<Navigate to="/inbox" replace />} />
    </Routes>
  );
}

function Signed({ list }: { list: ListName }) {
  const me = useMe();
  if (me.isPending) return <div className="splash" aria-busy="true"><Logo /></div>;
  if (me.isError) {
    return (
      <main className="signin">
        <div className="signin__card" role="alert">
          <Logo />
          <h1>Cubby is unreachable</h1>
          <p className="muted">The API didn't respond. Is it running on port 3000?</p>
          <button type="button" className="button button--primary" onClick={() => me.refetch()}>Try again</button>
        </div>
      </main>
    );
  }
  if (!me.data) return <Navigate to="/sign-in" replace />;
  return <Shell me={me.data} list={list} />;
}

function Shell({ me, list }: { me: Me; list: ListName }) {
  const client = useQueryClient();
  const navigate = useNavigate();
  const toast = useToast();
  const center = me.centers[0];
  const [asking, setAsking] = useState(false);
  const inbox = useQuery({
    queryKey: ["actions", center?.id, "inbox"],
    queryFn: () => api.actions(center!.id, "inbox"),
    enabled: Boolean(center),
  });

  const signOut = async () => {
    try {
      await api.signOut();
    } catch {
      toast("Couldn't reach Cubby to sign out. Try again.", "warning");
      return;
    }
    client.clear();
    client.setQueryData(["me"], null);
    navigate("/sign-in", { replace: true });
  };

  return (
    <div className="app">
      <header className="topbar">
        <div className="topbar__inner">
          <Logo />
          <div className="topbar__center">
            <span className="topbar__center-name">{center?.name ?? "No center"}</span>
            {center && <span className="muted">{center.city}</span>}
          </div>
          <div className="topbar__user">
            {center && (
              <button type="button" className="button button--primary button--small" onClick={() => setAsking(true)}>
                Ask Cubby
              </button>
            )}
            <span className="topbar__user-name">{me.user.name}</span>
            <button type="button" className="button button--quiet button--small" onClick={signOut}>Sign out</button>
          </div>
        </div>
      </header>

      <main className="page">
        <div className="page__head">
          <h1>{list === "inbox" ? "Today's queue" : list === "approved" ? "Approved" : "Dismissed"}</h1>
          <nav className="tabs" aria-label="Lists">
            <NavLink to="/inbox" className="tab">
              Inbox{inbox.data ? <span className="tab__count">{inbox.data.length}</span> : null}
            </NavLink>
            <NavLink to="/approved" className="tab">Approved</NavLink>
            <NavLink to="/dismissed" className="tab">Dismissed</NavLink>
          </nav>
        </div>
        {center ? (
          <Queue me={me} center={center} list={list} />
        ) : (
          <div className="empty"><h2>No center yet</h2><p className="muted">Ask an administrator to add you to a center.</p></div>
        )}
      </main>
      {asking && center && <AskPanel center={center} onClose={() => setAsking(false)} />}
    </div>
  );
}
