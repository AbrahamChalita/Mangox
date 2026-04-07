/** Mirrors iOS `ChatAPIResponse` + `ChatWireEvent` final payload. */

export interface SuggestedAction {
  label: string;
  type: string;
}

export interface CoachFollowUpBlock {
  question: string;
  suggestedActions: SuggestedAction[];
}

export interface ChatReference {
  title: string;
  url?: string;
  snippet?: string;
}

export interface CoachChatMessage {
  category: string;
  content: string;
  suggestedActions: SuggestedAction[];
  followUpQuestion: string | null;
  followUpBlocks: CoachFollowUpBlock[];
  confidence: number;
  thinkingSteps: string[];
  tags: string[];
  references: ChatReference[];
  toolCalls: unknown[];
  used_web_search: boolean;
}
