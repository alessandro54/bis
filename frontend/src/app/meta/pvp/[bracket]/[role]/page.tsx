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
        bracket: Bracket | string;
        role: string;
    }>;
    searchParams: Promise<{
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

function normalizeSpecName(value: string): string {
    return value.trim().toLowerCase().replace(/[-_\s]/g, "");
}

export default async function PvpBracketPage({params, searchParams}: PageProps) {
    const {bracket, role} = await params;
    const {region: regionParam, season: seasonParam} = await searchParams;
    const region = regionParam ?? "us";
    const season = seasonParam ?? "40";

    const data = await fetchClassDistribution({
        seasonId: season,
        role: role,
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
                            <BreadcrumbLink href="#">Meta</BreadcrumbLink>
                        </BreadcrumbItem>
                        <BreadcrumbSeparator className="hidden md:block"/>
                        <BreadcrumbItem>
                            <BreadcrumbPage>PvP</BreadcrumbPage>
                        </BreadcrumbItem>
                        <BreadcrumbSeparator className="hidden md:block"/>
                        <BreadcrumbItem>
                            <BreadcrumbPage>{bracket}</BreadcrumbPage>
                        </BreadcrumbItem>
                        <BreadcrumbSeparator className="hidden md:block"/>
                        <BreadcrumbItem>
                            <BreadcrumbPage>{role.toUpperCase()}</BreadcrumbPage>
                        </BreadcrumbItem>
                    </BreadcrumbList>
                </Breadcrumb>
            </header>
            <section className="mx-auto max-w-6xl space-y-4 p-4 flex flex-col flex-1 min-h-[calc(100vh-60px)]">
                <h1 className="text-3xl font-bold">
                    PvP meta – {bracket} {role.toUpperCase()}
                </h1>

                <p className="text-sm text-muted-foreground">
                    Region: <span className="font-mono">{region}</span> · Season: {" "}
                    <span className="font-mono">{season}</span>
                </p>

                <div className="rounded-lg flex flex-col flex-1 justify-center items-center py-4 min-h-[300px]">
                    <h2 className="text-lg font-semibold mb-4">Meta Score by Spec</h2>
                    <div className="w-full h-full flex items-center justify-center flex-1">
                        <div className="flex flex-row gap-2 overflow-x-auto pb-2 h-full items-end justify-center flex-1">
                            {topRows.map((row: any) => {
                                const classSlug = typeof row?.class === "string" ? normalizeClassSlug(row.class) : null;
                                const classConfig = classSlug
                                    ? WOW_CLASSES.find((c) => c.slug === classSlug)
                                    : undefined;
                                const specConfig = classConfig?.specs.find((s) => normalizeSpecName(s.name) === normalizeSpecName(row?.spec ?? ""));
                                const specName = row?.spec ?? "";
                                const metaScore = Number(row?.meta_score ?? 0);
                                const maxScore = Number(topRows[0]?.meta_score ?? 1);
                                const percentage = (metaScore / maxScore) * 100;

                                return (
                                    <div key={`bar-${row?.class ?? "unknown"}-${row?.spec_id ?? ""}`} className="flex flex-col items-center min-w-12 w-12 h-[400px]">
                                        <div className="flex flex-col items-center justify-end h-full w-full">
                                            <div className="w-8 bg-muted rounded-full flex items-end h-full">
                                                <div
                                                    className="w-full rounded-full transition-all"
                                                    style={{
                                                        height: `${percentage}%`,
                                                        backgroundColor: classConfig?.color ?? "#888",
                                                        minHeight: '8px',
                                                    }}
                                                />
                                            </div>
                                        </div>
                                        {specConfig?.iconUrl && (
                                            <img src={specConfig.iconUrl} alt={specName} className="h-6 w-6 rounded-full mb-1 mt-2"/>
                                        )}
                                        <span className="font-medium text-[10px] text-center truncate max-w-[40px]">{specName}</span>
                                    </div>
                                );
                            })}
                        </div>
                    </div>
                </div>
            </section>
        </>
    );
}
