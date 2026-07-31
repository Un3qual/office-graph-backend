export function SessionActions() {
  return (
    <form action="/auth/logout" className="ui-session-actions" method="post">
      <button className="ui-button ui-button-secondary" type="submit">
        Sign out
      </button>
    </form>
  );
}
