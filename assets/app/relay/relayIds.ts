type RelayIdTranslation<TInput extends object> = Partial<Record<keyof TInput, string>>;

export function relayGlobalId(type: string, id: string): string {
  const decoded = decodeRelayId(id);

  if (!decoded) {
    return btoa(`${type}:${id}`);
  }

  if (decoded.type !== type) {
    throw new Error(`Expected a ${type} Relay ID, received ${decoded.type}.`);
  }

  return id;
}

export function relayInternalId(type: string, id: string): string {
  const decoded = decodeRelayId(id);

  if (!decoded) {
    return id;
  }

  if (decoded.type !== type) {
    throw new Error(`Expected a ${type} Relay ID, received ${decoded.type}.`);
  }

  return decoded.id;
}

export function translateRelayMutationInput<TInput extends object>(
  input: TInput,
  translations: RelayIdTranslation<TInput>,
): TInput {
  return Object.fromEntries(
    Object.entries(input).map(([field, value]) => {
      const type = translations[field as keyof TInput];

      if (!type) {
        return [field, value];
      }

      if (Array.isArray(value)) {
        return [field, value.map((id) => relayGlobalId(type, id))];
      }

      return [field, typeof value === "string" ? relayGlobalId(type, value) : value];
    }),
  ) as TInput;
}

function decodeRelayId(value: string): { id: string; type: string } | null {
  try {
    const decoded = atob(value);
    const separator = decoded.indexOf(":");

    if (separator <= 0 || btoa(decoded) !== value) {
      return null;
    }

    return {
      type: decoded.slice(0, separator),
      id: decoded.slice(separator + 1),
    };
  } catch {
    return null;
  }
}
