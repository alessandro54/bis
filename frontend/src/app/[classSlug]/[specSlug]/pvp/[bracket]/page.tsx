// app/[classSlug]/[specSlug]/pvp/[bracket]/page.tsx
import {
    Breadcrumb,
    BreadcrumbList,
    BreadcrumbItem,
    BreadcrumbLink,
    BreadcrumbSeparator,
    BreadcrumbPage
} from "@/components/ui/breadcrumb";
import {SidebarTrigger} from "@/components/ui/sidebar";
import {WOW_CLASSES, type WowClassSlug, WowClassSpecSlug} from "@/config/wow/classes";
import {Separator} from "@radix-ui/react-separator";
import type {Metadata} from "next";

type Bracket =
    | "2v2"
    | "3v3"
    | "rbg"
    | "shuffle-overall"
    | "blitz-overall";

type PageProps = {
    params: Promise<{
        classSlug: string;
        specSlug: string;
        bracket: Bracket | string; // luego lo puedes validar
    }>;
    searchParams: Promise<{
        // por si luego quieres ?region=us&season=40 etc.
        region?: string;
        season?: string;
    }>;
};

export const metadata: Metadata = {
    title: "PvP Meta",
};

export const dynamic = "force-dynamic";

async function fetchClassDistribution(params: {
    seasonId: string;
    role: string;
    bracket: string;
    region: string;
}) {
    const baseUrl = process.env.BACKEND_URL ?? "http://localhost:3000";
    const url = new URL("/api/v1/pvp/meta/class_distribution", baseUrl);
    url.searchParams.set("season_id", params.seasonId);
    url.searchParams.set("role", params.role);
    url.searchParams.set("bracket", params.bracket);
    url.searchParams.set("region", params.region);

    const res = await fetch(url.toString(), {cache: "no-store"});
    if (!res.ok) {
        throw new Error(`Backend request failed: ${res.status} ${res.statusText}`);
    }
    return res.json();
}

function normalizeClassSlug(value: string): string {
    return value.trim().toLowerCase().replace(/_/g, "-");
}

export default async function PvpBracketPage({params, searchParams}: PageProps) {
    const {classSlug, specSlug, bracket} = await params;
    const {region: regionParam, season: seasonParam} = await searchParams;
    const region = regionParam ?? "us";
    const season = seasonParam ?? "40";

    const data = await fetchClassDistribution({
        seasonId: season,
        role: "dps",
        bracket: String(bracket),
        region
    });

    const topRows = (Array.isArray(data?.classes) ? data.classes : [])
        .slice()
        .sort((a: any, b: any) => (Number(b?.meta_score ?? 0) - Number(a?.meta_score ?? 0)));

    return (
        <>
            <header className="bg-background sticky top-0 flex shrink-0 items-center gap-2 border-b p-4 h-[60px]">
                <SidebarTrigger className="-ml-1"/>
                <Separator
                    orientation="vertical"
                    className="mr-2 data-[orientation=vertical]:h-4"
                />
                <Breadcrumb>
                    <BreadcrumbList>
                        <BreadcrumbItem className="hidden md:block">
                            <BreadcrumbLink href="#">Death Knight</BreadcrumbLink>
                        </BreadcrumbItem>
                        <BreadcrumbSeparator className="hidden md:block"/>
                        <BreadcrumbItem>
                            <BreadcrumbPage>Frost</BreadcrumbPage>
                        </BreadcrumbItem>
                        <BreadcrumbSeparator className="hidden md:block"/>
                        <BreadcrumbItem>
                            <BreadcrumbPage>3v3</BreadcrumbPage>
                        </BreadcrumbItem>
                    </BreadcrumbList>
                </Breadcrumb>
            </header>
            <section className="mx-auto max-w-5xl space-y-4 p-10 max-h-[calc(100vh-60px)] overflow-y-auto">
                <h1 className="text-3xl font-bold">
                    PvP meta – {classSlug} / {specSlug} / {bracket}
                </h1>

                <p className="text-sm text-muted-foreground">
                    Region: <span className="font-mono">{region}</span> · Season:{" "}
                    <span className="font-mono">{season}</span>
                </p>

                <div className="rounded-lg border p-4 mb-4">
                    <h2 className="text-lg font-semibold mb-4">Meta Score by Class</h2>
                    <div className="space-y-2">
                        {topRows.map((row: any) => {
                            const classSlug = typeof row?.class === "string" ? normalizeClassSlug(row.class) : null;
                            const classConfig = classSlug
                                ? WOW_CLASSES.find((c) => c.slug === classSlug)
                                : undefined;
                            const specConfig = classConfig?.specs.find((s) => s.name.toLowerCase() === (row?.spec?.toLowerCase() ?? ""));
                            const label = `${classConfig?.name ?? row?.class ?? "Unknown"} - ${row?.spec ?? ""}`;
                            const metaScore = Number(row?.meta_score ?? 0);
                            const maxScore = Number(topRows[0]?.meta_score ?? 1);
                            const percentage = (metaScore / maxScore) * 100;

                            return (
                                <div key={`bar-${row?.class ?? "unknown"}-${row?.spec_id ?? ""}`} className="space-y-1">
                                    <div className="flex items-center justify-between text-sm">
                                        <div className="flex items-center gap-2">
                                            {specConfig?.iconUrl && (
                                                <img src={specConfig.iconUrl} alt={label} className="h-5 w-5 rounded-full"/>
                                            )}
                                            <span className="font-medium">{label}</span>
                                        </div>
                                        <span className="font-mono text-muted-foreground">{metaScore.toFixed(4)}</span>
                                    </div>
                                    <div className="h-4 w-full rounded-full bg-muted overflow-hidden">
                                        <div
                                            className="h-full rounded-full transition-all"
                                            style={{
                                                width: `${percentage}%`,
                                                backgroundColor: classConfig?.color ?? "#888",
                                            }}
                                        />
                                    </div>
                                </div>
                            );
                        })}
                    </div>
                </div>
            </section>
        </>
    );
}
