import { NavLink } from "react-router";

export type NavDestination = {
  label: string;
  to?: string;
};

type Props = {
  ariaLabel: string;
  brand: string;
  items: readonly NavDestination[];
};

export function NavRail({ ariaLabel, brand, items }: Props) {
  return (
    <aside className="ui-nav-rail">
      <div className="ui-brand-mark" aria-hidden="true">
        {brand}
      </div>
      <nav aria-label={ariaLabel}>
        {items.map((item) => {
          const label = (
            <>
              <span aria-hidden="true">{item.label.slice(0, 1)}</span>
              <span>{item.label}</span>
            </>
          );

          return item.to !== undefined ? (
            <NavLink
              className={({ isActive }) =>
                isActive ? "ui-rail-item ui-rail-item-active" : "ui-rail-item"
              }
              key={item.label}
              to={item.to}
            >
              {label}
            </NavLink>
          ) : (
            <button className="ui-rail-item" disabled key={item.label}>
              {label}
            </button>
          );
        })}
      </nav>
    </aside>
  );
}
