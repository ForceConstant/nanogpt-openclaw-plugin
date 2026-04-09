export interface NanoGPTModel {
  id: string;
  provider?: string;
  name?: string;
  context_length?: number | null;
  max_output_tokens?: number | null;
  pricing?: {
    prompt?: number | null;
    completion?: number | null;
  } | null;
  capabilities?: {
    vision?: boolean;
    reasoning?: boolean;
  } | null;
}

export interface NanoGPTModelsResponse {
  object?: string;
  data?: NanoGPTModel[];
}


