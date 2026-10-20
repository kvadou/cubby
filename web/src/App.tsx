import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Navigate, NavLink, Route, Routes, useNavigate } from "react-router";
import { api } from "./api";
import { AskPanel } from "./components/AskPanel";
import { Logo } from "./components/Logo";
import { useToast } from "./components/Toasts";
import { Analytics } from "./pages/Analytics";
import { Queue } from "./pages/Queue";
import { SignIn } from "./pages/SignIn";
import { useMe } from "./session";
import type { ListName, Me } from "./types";

type Page = ListName | "analytics";

const TITLES: Record<Page, string> = { inbox: "Today's queue", approved: "Approved", dismissed: "Dismissed", analytics: "Analytics" };

export function App() {
  return (
    <Routes>
      <Route path="/sign-in" element={<SignIn />} />
      <Route path="/inbox" element={<Signed list="inbox" />} />
      <Route path="/approved" element={<Signed list="approved" />} />
      <Route path="/dismissed" element={<Signed list="dismissed" />} />
      <Route path="/analytics" element={<Signed list="analytics" />} />
      <Route path="*" element={<Navigate to="/inbox" replace />} />
    </Routes>
  );
}

function Signed({ list }: { list: Page }) {
  const me = useMe();
  if (me.isPending) return <div className="splash" aria-busy="true"><Logo /></div>;
  if (me.isError) {
    return (
      <main className="signin">
        <div className="signin__card" role="alert">
          <Logo />
          <h1>{import.meta.env.DEV ? "Cubby is unreachable" : "The demo is offline"}</h1>
          <p className="muted">
            {import.meta.env.DEV
              ? "The API didn't respond. Is it running on port 3000?"
              : "Cubby's servers run on demand and are switched off right now. Try again later."}
          </p>
          <button type="button" className="button button--primary" onClick={() => me.refetch()}>Try again</button>
        </div>
      </main>
    );
  }
  if (!me.data) return <Navigate to="/sign-in" replace />;
  if (me.data.centers.length === 0 && me.data.families.length > 0) return <FamilyOnly me={me.data} />;
  return <Shell me={me.data} list={list} />;
}

function useSignOut() {
  const client = useQueryClient();
  const navigate = useNavigate();
  const toast = useToast();
  return async () => {
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
}

// Parents use the mobile app; this web app is for center directors.
function FamilyOnly({ me }: { me: Me }) {
  const signOut = useSignOut();

  return (
    <main className="signin">
      <div className="signin__card">
        <Logo />
        <h1>Hi {me.user.name.split(" ")[0]}</h1>
        <p className="muted">
          This site is for center directors. Messages, check-ins, and tuition from {me.families[0]?.center_name ?? "your center"} are in
          the Cubby app on your phone.
        </p>
        <button type="button" className="button button--quiet" onClick={signOut}>Sign out</button>
      </div>
    </main>
  );
}

function Shell({ me, list }: { me: Me; list: Page }) {
  const signOut = useSignOut();
  const center = me.centers[0];
  const [asking, setAsking] = useState(false);
  const inbox = useQuery({
    queryKey: ["actions", center?.id, "inbox"],
    queryFn: () => api.actions(center!.id, "inbox"),
    enabled: Boolean(center),
  });

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
          <h1>{TITLES[list]}</h1>
          <nav className="tabs" aria-label="Lists">
            <NavLink to="/inbox" className="tab">
              Inbox{inbox.data ? <span className="tab__count">{inbox.data.length}</span> : null}
            </NavLink>
            <NavLink to="/approved" className="tab">Approved</NavLink>
            <NavLink to="/dismissed" className="tab">Dismissed</NavLink>
            <NavLink to="/analytics" className="tab">Analytics</NavLink>
          </nav>
        </div>
        {!center ? (
          <div className="empty"><h2>No center yet</h2><p className="muted">Ask an administrator to add you to a center.</p></div>
        ) : list === "analytics" ? (
          <Analytics center={center} />
        ) : (
          <Queue me={me} center={center} list={list} />
        )}
      </main>
      {asking && center && <AskPanel center={center} onClose={() => setAsking(false)} />}
    </div>
  );
}
