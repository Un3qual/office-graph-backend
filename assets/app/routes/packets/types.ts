export type FetchStatus = "idle" | "fetching";

export type QueryState<T> = {
  data: T | null;
  error: Error | null;
  fetchStatus: FetchStatus;
  isError: boolean;
  isPending: boolean;
  isSuccess: boolean;
};

export type PacketsPage = {
  first: number;
  after: string | null;
};

export type PacketConnection<TPacket> = {
  after: string | null;
  empty: boolean;
  first: number;
  hasNextPage: boolean;
  hasPreviousPage: boolean;
  nextCursor: string | null;
  startCursor: string | null;
  rows: TPacket[];
};
