import { Link } from "react-router";
import { Logo } from "../components/Logo";

interface Screen {
  file: string;
  title: string;
  caption: string;
}

const SCREENS: Screen[] = [
  { file: "today", title: "Today", caption: "Whether Meryl is checked in, then two weeks of drop-offs and pickups." },
  { file: "messages", title: "Messages", caption: "Notes the director approved in the queue, with unread ones marked." },
  { file: "billing", title: "Billing", caption: "Past-due tuition first, with the total due, then paid invoices." },
];

const PLATFORMS = [
  { id: "ios", name: "iPhone", stack: "SwiftUI, iOS 18 and later" },
  { id: "android", name: "Android", stack: "Kotlin and Jetpack Compose, Android 10 and later" },
] as const;

// Public: screenshots of the parent apps, which visitors can't install from a store.
export function Apps() {
  return (
    <main className="apps">
      <header className="apps__head">
        <Logo />
        <Link className="button button--quiet button--small" to="/sign-in">Back to the demo</Link>
      </header>
      <section className="apps__intro">
        <h1>The parent apps</h1>
        <p className="muted">
          Parents see check-ins, messages from the center, and tuition on their phone. Both apps use the same API as the
          director's queue, so when a director approves a note to a family, it lands in that family's inbox. These are the
          Russel family's screens from the demo data.
        </p>
      </section>
      {PLATFORMS.map((platform) => (
        <section key={platform.id} className="apps__platform" aria-labelledby={`${platform.id}-title`}>
          <div className="apps__platform-head">
            <h2 id={`${platform.id}-title`}>{platform.name}</h2>
            <span className="muted">{platform.stack}</span>
          </div>
          <ul className="apps__screens">
            {SCREENS.map((screen) => (
              <li key={screen.file}>
                <figure className="apps__screen">
                  <img
                    src={`/apps/${platform.id}-${screen.file}.png`}
                    alt={`${platform.name} app, ${screen.title} screen. ${screen.caption}`}
                    loading="lazy"
                    width={390}
                    height={844}
                  />
                  <figcaption>
                    <strong>{screen.title}</strong>
                    <span className="muted">{screen.caption}</span>
                  </figcaption>
                </figure>
              </li>
            ))}
          </ul>
        </section>
      ))}
    </main>
  );
}
