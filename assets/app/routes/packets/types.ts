export type PacketsPage = {
  first: number;
  after: string | null;
};

export type PacketRow = {
  readonly id: string;
  readonly title: string;
  readonly state: string;
  readonly currentVersionId: string | null | undefined;
  readonly operationId: string | null | undefined;
  readonly updatedAt: string;
};

export type PacketConnection<TPacket> = {
  hasNextPage: boolean;
  nextCursor: string | null;
  rows: TPacket[];
};
