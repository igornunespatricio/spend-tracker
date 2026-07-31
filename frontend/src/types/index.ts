export interface SpendingItem {
  PK: string;
  SK: string;
  itemId: string;
  userId: string;
  amount: string;
  category: Category;
  description: string;
  location: string;
  source: "manual" | "photo";
  jobId?: string;
  photoKey?: string;
  createdAt: string;
  updatedAt: string;
}

export type Category =
  | "FOOD"
  | "TRANSPORT"
  | "HEALTH"
  | "ENTERTAINMENT"
  | "CLOTHING"
  | "UTILITIES"
  | "OTHER";

export const CATEGORIES: Category[] = [
  "FOOD",
  "TRANSPORT",
  "HEALTH",
  "ENTERTAINMENT",
  "CLOTHING",
  "UTILITIES",
  "OTHER",
];

export const CATEGORY_LABELS: Record<Category, string> = {
  FOOD: "🍽️ Food",
  TRANSPORT: "🚗 Transport",
  HEALTH: "💊 Health",
  ENTERTAINMENT: "🎬 Entertainment",
  CLOTHING: "👕 Clothing",
  UTILITIES: "⚡ Utilities",
  OTHER: "📦 Other",
};

export const CATEGORY_COLORS: Record<Category, string> = {
  FOOD: "#3b82f6",
  TRANSPORT: "#8b5cf6",
  HEALTH: "#22c55e",
  ENTERTAINMENT: "#f59e0b",
  CLOTHING: "#ec4899",
  UTILITIES: "#14b8a6",
  OTHER: "#94a3b8",
};

export type JobStatus =
  | "CREATED"
  | "PROCESSING"
  | "PENDING_REVIEW"
  | "CONFIRMED"
  | "FAILED";

export interface ExtractedItem {
  id: string;
  description: string;
  amount: string;
  category: Category;
  location: string;
}

export interface ProcessingJob {
  PK: string;
  SK: string;
  jobId: string;
  userId: string;
  s3Key: string;
  modelId: string;
  status: JobStatus;
  extractedItems: ExtractedItem[];
  errorMessage?: string;
  modelUsed?: string;
  createdAt: string;
  updatedAt: string;
}

export interface BedrockModel {
  id: string;
  label: string;
  description: string;
}

export const BEDROCK_MODELS: BedrockModel[] = [
  {
    id: "anthropic.claude-3-haiku-20240307-v1:0",
    label: "Claude 3 Haiku",
    description: "Fast & cost-effective (default)",
  },
  {
    id: "anthropic.claude-3-5-haiku-20241022-v1:0",
    label: "Claude 3.5 Haiku",
    description: "Balanced speed & accuracy",
  },
  {
    id: "anthropic.claude-3-5-sonnet-20241022-v2:0",
    label: "Claude 3.5 Sonnet",
    description: "High accuracy",
  },
  {
    id: "anthropic.claude-3-opus-20240229-v1:0",
    label: "Claude 3 Opus",
    description: "Best quality (slower & costlier)",
  },
];

export interface DateRange {
  from: string;
  to: string;
}

export interface SpendingSummary {
  totalAmount: number;
  byCategory: Record<Category, number>;
  byLocation: Record<string, number>;
  itemCount: number;
}
