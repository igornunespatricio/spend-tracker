import axios from "axios";
import { getSession } from "./auth";
import type { SpendingItem, ProcessingJob, DateRange } from "@/types";

const BASE_URL = import.meta.env.VITE_API_URL ?? "";

const http = axios.create({ baseURL: BASE_URL });

http.interceptors.request.use(async (config) => {
  const session = await getSession();
  if (session) {
    config.headers.Authorization = `Bearer ${session.idToken}`;
  }
  return config;
});

// ── Spending ──────────────────────────────────────────────────────────────────

export async function listSpending(range: DateRange): Promise<SpendingItem[]> {
  const { data } = await http.get<{ items: SpendingItem[] }>("/api/spending", {
    params: { from: range.from, to: range.to },
  });
  return data.items;
}

export async function createSpending(
  payload: Pick<SpendingItem, "amount" | "category" | "description" | "location">
): Promise<SpendingItem> {
  const { data } = await http.post<{ item: SpendingItem }>("/api/spending", payload);
  return data.item;
}

export async function deleteSpending(itemId: string): Promise<void> {
  await http.delete(`/api/spending/${itemId}`);
}

export async function listCategories(): Promise<string[]> {
  const { data } = await http.get<{ categories: string[] }>("/api/categories");
  return data.categories;
}

// ── Processing Jobs ───────────────────────────────────────────────────────────

export async function createJob(modelId: string): Promise<{ jobId: string; uploadUrl: string; s3Key: string }> {
  const { data } = await http.post("/api/jobs", { modelId });
  return data;
}

export async function uploadPhoto(uploadUrl: string, file: File): Promise<void> {
  await axios.put(uploadUrl, file, {
    headers: { "Content-Type": "image/jpeg" },
  });
}

export async function submitJob(jobId: string): Promise<void> {
  await http.post(`/api/jobs/${jobId}/submit`);
}

export async function getJob(jobId: string): Promise<ProcessingJob> {
  const { data } = await http.get<{ job: ProcessingJob }>(`/api/jobs/${jobId}`);
  return data.job;
}

export async function confirmJob(
  jobId: string,
  items: Array<{ description: string; amount: string; category: string; location: string }>
): Promise<{ savedCount: number }> {
  const { data } = await http.put(`/api/jobs/${jobId}/confirm`, { items });
  return data;
}
