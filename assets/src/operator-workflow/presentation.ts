export function listSummary(values: string[], limit = 3) {
  const uniqueValues = [...new Set(values.map((value) => value.trim()).filter(Boolean))];

  if (uniqueValues.length === 0) {
    return "None";
  }

  const visibleValues = uniqueValues.slice(0, limit);
  const hiddenCount = uniqueValues.length - visibleValues.length;

  if (hiddenCount === 0) {
    return visibleValues.join(", ");
  }

  return `${visibleValues.join(", ")}, and ${hiddenCount} more`;
}

export function shortId(id: string | null) {
  if (!id) {
    return "none";
  }

  return id.split("-")[0] || id;
}
