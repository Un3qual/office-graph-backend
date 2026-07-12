const packetUpdatedAtFormatter = new Intl.DateTimeFormat("en-US", {
  day: "numeric",
  hour: "numeric",
  minute: "2-digit",
  month: "short",
  timeZone: "UTC",
  year: "numeric",
});

export function formatPacketUpdatedAt(value: string) {
  return `${packetUpdatedAtFormatter.format(new Date(value))} UTC`;
}

export function formatPacketState(value: string) {
  const words = value.replaceAll("_", " ").toLowerCase();

  return words.charAt(0).toUpperCase() + words.slice(1);
}
