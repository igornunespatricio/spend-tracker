import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { useForm } from "react-hook-form";
import { z } from "zod";
import { zodResolver } from "@hookform/resolvers/zod";
import { CheckCircle } from "lucide-react";
import { useCreateSpending } from "@/hooks/useSpending";
import { CATEGORIES, CATEGORY_LABELS } from "@/types";
import type { Category } from "@/types";

const schema = z.object({
  amount: z.string().regex(/^\d+(\.\d{1,2})?$/, "Enter a valid amount (e.g. 12.50)"),
  category: z.enum(CATEGORIES as [Category, ...Category[]]),
  description: z.string().min(2, "Description is required").max(500),
  location: z.string().max(200).optional(),
});
type FormValues = z.infer<typeof schema>;

export default function ManualInput(): JSX.Element {
  const navigate = useNavigate();
  const mutation = useCreateSpending();
  const [saved, setSaved] = useState(false);

  const {
    register,
    handleSubmit,
    reset,
    formState: { errors, isSubmitting },
  } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: { category: "FOOD" },
  });

  async function onSubmit(values: FormValues): Promise<void> {
    await mutation.mutateAsync({
      amount: values.amount,
      category: values.category,
      description: values.description,
      location: values.location ?? "",
    });
    setSaved(true);
    reset();
    setTimeout(() => {
      setSaved(false);
      navigate("/dashboard");
    }, 1500);
  }

  return (
    <div className="p-4 max-w-lg mx-auto">
      <h1 className="text-lg font-bold text-gray-900 mb-5">Add Expense</h1>

      {saved && (
        <div className="flex items-center gap-2 bg-green-50 border border-green-200 rounded-xl px-4 py-3 mb-4 text-green-700 text-sm">
          <CheckCircle size={16} />
          Saved! Redirecting…
        </div>
      )}

      <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
        {/* Amount */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Amount ($)</label>
          <div className="relative">
            <span className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 text-sm">$</span>
            <input
              {...register("amount")}
              type="number"
              step="0.01"
              min="0"
              inputMode="decimal"
              className="w-full pl-7 pr-4 py-3 rounded-xl border border-gray-300 focus:outline-none focus:ring-2 focus:ring-primary-500 text-sm"
              placeholder="0.00"
            />
          </div>
          {errors.amount && <p className="mt-1 text-xs text-red-500">{errors.amount.message}</p>}
        </div>

        {/* Category */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Category</label>
          <div className="grid grid-cols-3 gap-2">
            {CATEGORIES.map((cat) => (
              <label key={cat} className="cursor-pointer">
                <input {...register("category")} type="radio" value={cat} className="sr-only peer" />
                <div className="text-center py-2 px-1 rounded-xl border border-gray-300 peer-checked:border-primary-500 peer-checked:bg-primary-50 peer-checked:text-primary-700 text-xs font-medium text-gray-600 transition-colors">
                  {CATEGORY_LABELS[cat]}
                </div>
              </label>
            ))}
          </div>
          {errors.category && <p className="mt-1 text-xs text-red-500">{errors.category.message}</p>}
        </div>

        {/* Description */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Description</label>
          <input
            {...register("description")}
            type="text"
            className="w-full px-4 py-3 rounded-xl border border-gray-300 focus:outline-none focus:ring-2 focus:ring-primary-500 text-sm"
            placeholder="What did you buy?"
          />
          {errors.description && <p className="mt-1 text-xs text-red-500">{errors.description.message}</p>}
        </div>

        {/* Location */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Location (optional)</label>
          <input
            {...register("location")}
            type="text"
            className="w-full px-4 py-3 rounded-xl border border-gray-300 focus:outline-none focus:ring-2 focus:ring-primary-500 text-sm"
            placeholder="Store name"
          />
        </div>

        {mutation.error && (
          <div className="rounded-xl bg-red-50 border border-red-200 px-4 py-3 text-sm text-red-700">
            Failed to save. Please try again.
          </div>
        )}

        <button
          type="submit"
          disabled={isSubmitting || saved}
          className="w-full py-3 px-4 bg-primary-600 hover:bg-primary-700 disabled:opacity-60 text-white font-semibold rounded-xl transition-colors text-sm"
        >
          {isSubmitting ? "Saving…" : "Save Expense"}
        </button>
      </form>
    </div>
  );
}
