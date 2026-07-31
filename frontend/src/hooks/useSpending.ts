import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { listSpending, createSpending, deleteSpending } from "@/services/api";
import type { SpendingItem, DateRange, SpendingSummary, Category } from "@/types";
import { CATEGORY_COLORS } from "@/types";

export function useSpending(range: DateRange) {
  return useQuery({
    queryKey: ["spending", range.from, range.to],
    queryFn: () => listSpending(range),
    select: (items) => {
      const summary: SpendingSummary = {
        totalAmount: 0,
        byCategory: {} as Record<Category, number>,
        byLocation: {},
        itemCount: items.length,
      };

      for (const item of items) {
        const amount = parseFloat(item.amount);
        summary.totalAmount += amount;
        summary.byCategory[item.category] = (summary.byCategory[item.category] ?? 0) + amount;
        if (item.location) {
          summary.byLocation[item.location] = (summary.byLocation[item.location] ?? 0) + amount;
        }
      }

      return { items, summary };
    },
  });
}

export function useCreateSpending() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: createSpending,
    onSuccess: () => qc.invalidateQueries({ queryKey: ["spending"] }),
  });
}

export function useDeleteSpending() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (itemId: string) => deleteSpending(itemId),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["spending"] }),
  });
}

export function useCategoryChartData(byCategory: Record<Category, number>) {
  return Object.entries(byCategory).map(([category, value]) => ({
    name: category,
    value: Math.round(value * 100) / 100,
    fill: CATEGORY_COLORS[category as Category] ?? "#94a3b8",
  }));
}
