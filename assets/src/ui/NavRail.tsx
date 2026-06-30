type NavItem = {
  label: string;
  state?: "current" | "available" | "unavailable";
};

type Props = {
  ariaLabel: string;
  brand: string;
  items: NavItem[];
};

export function NavRail({ ariaLabel, brand, items }: Props) {
  return (
    <aside className="ui-nav-rail">
      <div className="ui-brand-mark" aria-hidden="true">
        {brand}
      </div>
      <nav aria-label={ariaLabel}>
        {items.map((item) => {
          const isCurrent = item.state === "current";
          const isUnavailable = item.state === "unavailable";

          return (
            <button
              aria-current={isCurrent ? "page" : undefined}
              className={isCurrent ? "ui-rail-item ui-rail-item-active" : "ui-rail-item"}
              disabled={isUnavailable}
              key={item.label}
            >
              <span aria-hidden="true">{item.label.slice(0, 1)}</span>
              <span>{item.label}</span>
            </button>
          );
        })}
      </nav>
    </aside>
  );
}
