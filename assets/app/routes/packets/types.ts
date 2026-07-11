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

export type PacketCommandInputDefault = {
  readonly field: string;
  readonly value: string | null | undefined;
  readonly values: readonly string[];
};

export type PacketCommandAffordance = {
  readonly identity: string;
  readonly state: string;
  readonly reasonCodes: readonly string[];
  readonly blockerReasons: readonly string[];
  readonly safeExplanation: string;
  readonly requiredFields: readonly string[];
  readonly inputDefaults: readonly PacketCommandInputDefault[];
};

export type PacketWorkspaceVersion = {
  readonly id: string;
  readonly versionNumber: number;
  readonly lifecycleState: string;
  readonly title: string;
  readonly objective: string;
  readonly contextSummary: string;
  readonly requirements: string;
  readonly successCriteria: string | null | undefined;
  readonly autonomyPosture: string;
  readonly sourceGraphItemIds: readonly string[];
  readonly verificationCheckIds: readonly string[];
  readonly operationId: string;
  readonly insertedAt: string;
};

export type PacketWorkspaceDetail = {
  readonly sourceWatermark: string;
  readonly ready: boolean;
  readonly status: string;
  readonly blockerReasons: readonly string[];
  readonly allowedNextActions: readonly string[];
  readonly packet: {
    readonly id: string;
    readonly title: string;
    readonly state: string;
    readonly currentVersionId: string;
    readonly operationId: string | null | undefined;
  };
  readonly currentVersion: PacketWorkspaceVersion;
  readonly versions: readonly PacketWorkspaceVersion[];
  readonly commandAffordances: readonly PacketCommandAffordance[];
};
