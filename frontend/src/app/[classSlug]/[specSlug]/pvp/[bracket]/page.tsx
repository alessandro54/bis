// app/[classSlug]/[specSlug]/pvp/[bracket]/page.tsx
import { Breadcrumb, BreadcrumbList, BreadcrumbItem, BreadcrumbLink, BreadcrumbSeparator, BreadcrumbPage } from "@/components/ui/breadcrumb";
import { SidebarTrigger } from "@/components/ui/sidebar";
import { Separator } from "@radix-ui/react-separator";
import type { Metadata } from "next";

type Bracket =
    | "2v2"
    | "3v3"
    | "rbg"
    | "shuffle-overall"
    | "blitz-overall";

type PageProps = {
    params: {
        classSlug: string;
        specSlug: string;
        bracket: Bracket | string; // luego lo puedes validar
    };
    searchParams: {
        // por si luego quieres ?region=us&season=40 etc.
        region?: string;
        season?: string;
    };
};

export const metadata: Metadata = {
    title: "PvP Meta",
};

export default function PvpBracketPage({ params, searchParams }: PageProps) {
    const { classSlug, specSlug, bracket } = params;
    const region = searchParams.region ?? "us";
    const season = searchParams.season ?? "40";

    // Aquí luego harás fetch a tu Rails API, por ahora sólo stub
    // const data = await fetchMeta({ classSlug, specSlug, bracket, region, season })

    return (
        <>
            <header className="bg-background sticky top-0 flex shrink-0 items-center gap-2 border-b p-4 h-[60px]">
                <SidebarTrigger className="-ml-1" />
                <Separator
                    orientation="vertical"
                    className="mr-2 data-[orientation=vertical]:h-4"
                />
                <Breadcrumb>
                    <BreadcrumbList>
                        <BreadcrumbItem className="hidden md:block">
                            <BreadcrumbLink href="#">Death Knight</BreadcrumbLink>
                        </BreadcrumbItem>
                        <BreadcrumbSeparator className="hidden md:block" />
                        <BreadcrumbItem>
                            <BreadcrumbPage>Frost</BreadcrumbPage>
                        </BreadcrumbItem>
                        <BreadcrumbSeparator className="hidden md:block" />
                        <BreadcrumbItem>
                            <BreadcrumbPage>3v3</BreadcrumbPage>
                        </BreadcrumbItem>
                    </BreadcrumbList>
                </Breadcrumb>
            </header>
            <section className="mx-auto max-w-5xl space-y-4 p-10">
                <h1 className="text-3xl font-bold">
                    PvP meta – {classSlug} / {specSlug} / {bracket}
                </h1>

                <p className="text-sm text-muted-foreground">
                    Region: <span className="font-mono">{region}</span> · Season:{" "}
                    <span className="font-mono">{season}</span>
                </p>

                {/* Aquí irá tu UI con shadcn (cards, tables, charts, etc.) */}
                <div className="rounded-lg border p-4">
                    <p className="text-sm">
                        Aquí mostraremos stats de popularidad, rating medio y equipo para esta
                        combinación de clase, spec y bracket.
                    </p>
                </div>
            </section>
        </>
    );
}
