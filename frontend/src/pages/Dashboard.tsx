import { useState } from "react";
import { format, subDays, startOfMonth, endOfMonth } from "date-fns";
import {
  PieChart, Pie, Cell, Tooltip, BarChart, Bar, XAxis, YAxis,
  LineChart, Line, ResponsiveContainer, CartesianGrid, Legend,
} from "recharts";
import { Calendar, TrendingUp, Trash2 } from "lucide-react";
import { useSpending, useCategoryChartData, useDeleteSpending } from "@/hooks/useSpending";
import { CATEGORY_LABELS, CATEGORY_COLORS } from "@/types";
import type { DateRange, SpendingItem } from "@/types";

const DATE_PRESETS = [
  { label: "Last 7d", range: () => ({ from: format(subDays(new Date(), 7), "yyyy-MM-dd"), to: format(new Date(), "yyyy-MM-dd") }) },
  { label: "This month", range: () => ({ from: format(startOfMonth(new Date()), "yyyy-MM-dd"), to: format(endOfMonth(new Date()), "yyyy-MM-dd") }) },
  { label: "Last 30d", range: () => ({ from: format(subDays(new Date(), 30), "yyyy-MM-dd"), to: format(new Date(), "yyyy-MM-dd") }) },
];

export default function Dashboard(): JSX.Element {
  const [range, setRange] = useState<DateRange>({
    from: format(startOfMonth(new Date()), "yyyy-MM-dd"),
    to: format(new Date(), "yyyy-MM-dd"),
  });
  const [activePreset, setActivePreset] = useState(1);

  const { data, isLoading, error } = useSpending(range);
  const deleteMutation = useDeleteSpending();
  const categoryData = useCategoryChartData(data?.summary.byCategory ?? {} as never);

  function applyPreset(idx: number): void {
    setActivePreset(idx);
    setRange(DATE_PRESETS[idx].range());
  }

  if (isLoading) return <LoadingState />;
  if (error) return <ErrorState />;

  const { items = [], summary } = data ?? { items: [], summary: { totalAmount: 0, byCategory: {}, byLocation: {}, itemCount: 0 } };

  const topLocations = Object.entries(summary.byLocation)
    .sort(([, a], [, b]) => b - a)
    .slice(0, 5)
    .map(([name, value]) => ({ name, value: Math.round(value * 100) / 100 }));

  return (
    <div className="p-4 space-y-5">
      {/* Date range selector */}
      <div>
        <div className="flex gap-2 mb-2">
          {DATE_PRESETS.map((p, i) => (
            <button
              key={p.label}
              onClick={() => applyPreset(i)}
              className={`px-3 py-1.5 rounded-full text-xs font-medium transition-colors ${
                activePreset === i
                  ? "bg-primary-600 text-white"
                  : "bg-white text-gray-600 border border-gray-300"
              }`}
            >
              {p.label}
            </button>
          ))}
        </div>
        <div className="flex gap-2 items-center text-xs text-gray-500">
          <Calendar size={13} />
          <span>{range.from} → {range.to}</span>
        </div>
      </div>

      {/* Summary card */}
      <div className="bg-primary-600 rounded-2xl p-5 text-white">
        <p className="text-primary-100 text-sm">Total spending</p>
        <p className="text-3xl font-bold mt-1">
          ${summary.totalAmount.toFixed(2)}
        </p>
        <p className="text-primary-100 text-xs mt-2 flex items-center gap-1">
          <TrendingUp size={12} /> {summary.itemCount} transactions
        </p>
      </div>

      {/* Category breakdown */}
      {categoryData.length > 0 && (
        <div className="bg-white rounded-2xl p-4 shadow-sm">
          <h2 className="text-sm font-semibold text-gray-700 mb-3">By Category</h2>
          <ResponsiveContainer width="100%" height={180}>
            <PieChart>
              <Pie data={categoryData} dataKey="value" nameKey="name" cx="50%" cy="50%" outerRadius={70} label={false}>
                {categoryData.map((entry) => (
                  <Cell key={entry.name} fill={entry.fill} />
                ))}
              </Pie>
              <Tooltip formatter={(v: number) => `$${v.toFixed(2)}`} />
              <Legend
                formatter={(v) => CATEGORY_LABELS[v as keyof typeof CATEGORY_LABELS] ?? v}
                wrapperStyle={{ fontSize: 11 }}
              />
            </PieChart>
          </ResponsiveContainer>
        </div>
      )}

      {/* Top locations */}
      {topLocations.length > 0 && (
        <div className="bg-white rounded-2xl p-4 shadow-sm">
          <h2 className="text-sm font-semibold text-gray-700 mb-3">Top Locations</h2>
          <ResponsiveContainer width="100%" height={160}>
            <BarChart data={topLocations} layout="vertical" margin={{ left: 0, right: 16 }}>
              <CartesianGrid strokeDasharray="3 3" horizontal={false} />
              <XAxis type="number" tick={{ fontSize: 10 }} tickFormatter={(v) => `$${v}`} />
              <YAxis type="category" dataKey="name" tick={{ fontSize: 10 }} width={80} />
              <Tooltip formatter={(v: number) => `$${v.toFixed(2)}`} />
              <Bar dataKey="value" fill="#3b82f6" radius={[0, 4, 4, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </div>
      )}

      {/* Recent transactions */}
      {items.length > 0 && (
        <div className="bg-white rounded-2xl shadow-sm overflow-hidden">
          <h2 className="text-sm font-semibold text-gray-700 px-4 pt-4 pb-2">Recent Transactions</h2>
          <ul className="divide-y divide-gray-100">
            {items.slice(0, 20).map((item) => (
              <TransactionRow key={item.itemId} item={item} onDelete={() => deleteMutation.mutate(item.itemId)} />
            ))}
          </ul>
        </div>
      )}

      {items.length === 0 && (
        <div className="text-center py-12 text-gray-400">
          <p className="text-4xl mb-3">📭</p>
          <p className="text-sm">No transactions in this period.</p>
        </div>
      )}
    </div>
  );
}

function TransactionRow({ item, onDelete }: { item: SpendingItem; onDelete: () => void }): JSX.Element {
  const color = CATEGORY_COLORS[item.category] ?? "#94a3b8";
  return (
    <li className="flex items-center gap-3 px-4 py-3">
      <div className="w-8 h-8 rounded-full flex-shrink-0" style={{ backgroundColor: `${color}22` }}>
        <span className="flex items-center justify-center h-full text-sm">
          {CATEGORY_LABELS[item.category]?.split(" ")[0] ?? "📦"}
        </span>
      </div>
      <div className="flex-1 min-w-0">
        <p className="text-sm font-medium text-gray-800 truncate">{item.description}</p>
        <p className="text-xs text-gray-400 truncate">{item.location || item.category}</p>
      </div>
      <div className="text-right flex items-center gap-2">
        <div>
          <p className="text-sm font-semibold text-gray-800">${parseFloat(item.amount).toFixed(2)}</p>
          <p className="text-xs text-gray-400">{item.createdAt.slice(0, 10)}</p>
        </div>
        <button
          onClick={onDelete}
          className="text-gray-300 hover:text-red-400 transition-colors p-1"
          aria-label="Delete"
        >
          <Trash2 size={14} />
        </button>
      </div>
    </li>
  );
}

function LoadingState(): JSX.Element {
  return (
    <div className="p-4 space-y-4">
      {[1, 2, 3].map((i) => (
        <div key={i} className="bg-white rounded-2xl h-32 animate-pulse" />
      ))}
    </div>
  );
}

function ErrorState(): JSX.Element {
  return (
    <div className="p-4 text-center text-red-500 text-sm">
      Failed to load spending data. Please try again.
    </div>
  );
}
