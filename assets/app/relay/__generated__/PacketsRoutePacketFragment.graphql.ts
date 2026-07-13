/**
 * @generated SignedSource<<49bdc3ec4d5f7fffaf03b39932f1bc43>>
 * @lightSyntaxTransform
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderInlineDataFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type PacketsRoutePacketFragment$data = {
  readonly currentVersionId: string | null | undefined;
  readonly id: string;
  readonly operationId: string | null | undefined;
  readonly state: string;
  readonly title: string;
  readonly updatedAt: string;
  readonly " $fragmentType": "PacketsRoutePacketFragment";
};
export type PacketsRoutePacketFragment$key = {
  readonly " $data"?: PacketsRoutePacketFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"PacketsRoutePacketFragment">;
};

const node: ReaderInlineDataFragment = {
  "kind": "InlineDataFragment",
  "name": "PacketsRoutePacketFragment"
};

(node as any).hash = "804bbe7155d110b29a499b5e64ff661a";

export default node;
