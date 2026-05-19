/**
 * pdf-helpers.ts — shared PDF generation and retrieval utilities for OtterQuote.
 *
 * Extracted from create-docusign-envelope/index.ts to bring that file below the
 * 2,000-line architectural threshold and improve maintainability.
 *
 * Exports:
 *   base64EncodeBinary          – Uint8Array → base64 string
 *   getTemplateFromStorage      – fetch contractor PDF template from Supabase storage
 *   fetchTemplateFromUrl        – fetch PDF template from a public URL
 *   getPcTemplateFromStorage    – fetch personal-care template from Supabase storage
 *   selectPcTemplateSlot        – pick the correct PC template slot by trade/funding
 *   generateComplianceAddendumPdf – IC 24-5-11 right-to-cancel addendum
 *   generateRetailScopeOfWorkPdf  – retail scope-of-work document
 */

// ========== PDF RETRIEVAL ==========
export async function getTemplateFromStorage(
  supabase: any,
  contractorId: string,
  documentType: string
): Promise<string> {
  const bucketName = "contractor-templates";
  const filePath = `${contractorId}/${documentType}.pdf`;

  try {
    const { data, error } = await supabase.storage
      .from(bucketName)
      .download(filePath);

    if (error) {
      throw new Error(`Storage error: ${error.message}`);
    }

    if (!data) {
      throw new Error("No data returned from storage");
    }

    const arrayBuffer = await data.arrayBuffer();
    const base64 = base64EncodeBinary(new Uint8Array(arrayBuffer));
    return base64;
  } catch (err) {
    throw new Error(
      `Failed to retrieve template PDF (${bucketName}/${filePath}): ${err.message}`
    );
  }
}

export async function fetchTemplateFromUrl(url: string): Promise<string> {
  console.log(`Fetching template PDF from URL: ${url}`);
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(
      `Failed to fetch template from URL (${response.status} ${response.statusText}): ${url}`
    );
  }
  const arrayBuffer = await response.arrayBuffer();
  return base64EncodeBinary(new Uint8Array(arrayBuffer));
}

export async function getPcTemplateFromStorage(supabase: any, fileUrl: string): Promise<string> {
  let storagePath: string;
  const pathMatch = fileUrl.match(/contractor-templates\/(.+?)(\?|$)/);
  if (pathMatch) {
    storagePath = decodeURIComponent(pathMatch[1]);
  } else {
    storagePath = fileUrl;
  }

  console.log(`Fetching PC template from storage: contractor-templates/${storagePath}`);
  const { data, error } = await supabase.storage
    .from("contractor-templates")
    .download(storagePath);

  if (error) {
    throw new Error(`PC template storage error (${storagePath}): ${error.message}`);
  }
  if (!data) {
    throw new Error(`No data returned from storage for PC template: ${storagePath}`);
  }

  const arrayBuffer = await data.arrayBuffer();
  return base64EncodeBinary(new Uint8Array(arrayBuffer));
}

export function selectPcTemplateSlot(
  pcTemplateJsonb: Record<string, any> | null | undefined,
  trade: string,
  fundingType: string
): { file_url: string; uploaded_at: string } | null {
  if (!pcTemplateJsonb || typeof pcTemplateJsonb !== "object") return null;

  const primaryKey  = `${trade.toLowerCase()}/${fundingType.toLowerCase()}`;
  const fallbackKey = "roofing/insurance";

  const primary  = pcTemplateJsonb[primaryKey];
  if (primary?.file_url) {
    console.log(`PC template: using slot ${primaryKey}`);
    return primary;
  }

  const fallback = pcTemplateJsonb[fallbackKey];
  if (fallback?.file_url) {
    console.warn(`PC template: slot ${primaryKey} missing — falling back to ${fallbackKey}`);
    return fallback;
  }

  console.warn(`PC template: no usable slot found (tried ${primaryKey} and ${fallbackKey})`);
  return null;
}

export function base64EncodeBinary(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.byteLength; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}


// ========== IC 24-5-11 COMPLIANCE ADDENDUM PDF ==========
export function generateComplianceAddendumPdf(contractorName: string, homeownerName: string, contractDate: string): string {
  const lines: string[] = [];
  const objects: { offset: number }[] = [];
  let currentOffset = 0;

  function write(s: string) {
    lines.push(s);
    currentOffset += s.length + 1;
  }

  function startObject(num: number) {
    objects[num] = { offset: currentOffset };
    write(`${num} 0 obj`);
  }

  const signDate = new Date(contractDate || new Date().toISOString());
  let businessDays = 0;
  const cancelDate = new Date(signDate);
  while (businessDays < 3) {
    cancelDate.setDate(cancelDate.getDate() + 1);
    const dow = cancelDate.getDay();
    if (dow !== 0 && dow !== 6) businessDays++;
  }
  const cancelDateStr = cancelDate.toLocaleDateString("en-US", { month: "long", day: "numeric", year: "numeric" });

  const contentLines: string[] = [];

  function addText(x: number, y: number, fontSize: number, font: string, text: string) {
    const escaped = text.replace(/\\/g, "\\\\").replace(/\(/g, "\\(").replace(/\)/g, "\\)");
    contentLines.push(`BT /${font} ${fontSize} Tf ${x} ${y} Td (${escaped}) Tj ET`);
  }

  function addWrappedText(x: number, startY: number, fontSize: number, font: string, text: string, maxWidth: number): number {
    const charWidth = fontSize * 0.5;
    const maxChars = Math.floor(maxWidth / charWidth);
    const words = text.split(" ");
    let currentLine = "";
    let y = startY;
    const lineSpacing = fontSize * 1.4;

    for (const word of words) {
      if (currentLine.length + word.length + 1 > maxChars) {
        addText(x, y, fontSize, font, currentLine.trim());
        y -= lineSpacing;
        currentLine = word + " ";
      } else {
        currentLine += word + " ";
      }
    }
    if (currentLine.trim()) {
      addText(x, y, fontSize, font, currentLine.trim());
      y -= lineSpacing;
    }
    return y;
  }

  let y = 750;

  addText(50, y, 14, "F2", "INDIANA HOME IMPROVEMENT CONTRACT ACT ADDENDUM");
  y -= 20;
  addText(50, y, 10, "F1", `IC 24-5-11 Compliance Addendum — Contract Date: ${contractDate || new Date().toLocaleDateString("en-US")}`);
  y -= 10;

  contentLines.push(`50 ${y} m 562 ${y} l S`);
  y -= 20;

  addText(50, y, 12, "F2", "STATEMENT OF RIGHT TO CANCEL");
  y -= 20;

  const statementText = `You may cancel this contract at any time before midnight on the third business day after the later of the following: (A) The date this contract is signed by you and ${contractorName}. (B) If applicable, the date you receive written notification from your insurance company of a final determination as to whether all or any part of your claim or this contract is a covered loss under your insurance policy. See attached notice of cancellation form for an explanation of this right.`;

  y = addWrappedText(50, y, 10, "F2", statementText, 512);
  y -= 15;

  contentLines.push(`50 ${y + 5} m 562 ${y + 5} l S`);
  y -= 15;

  addText(50, y, 12, "F2", "NOTICE OF CANCELLATION");
  y -= 20;

  addText(50, y, 10, "F2", `Contract Date: ${contractDate || "_______________"}`);
  y -= 16;

  y = addWrappedText(50, y, 10, "F2",
    `You may CANCEL this transaction, without any penalty or obligation, within THREE (3) BUSINESS DAYS from the above date, or if applicable, within three (3) business days from the date you receive written notification from your insurance company of a final determination as to whether all or any part of your claim or this contract is a covered loss under your insurance policy.`,
    512);
  y -= 10;

  y = addWrappedText(50, y, 10, "F2",
    `If you cancel, any property traded in, any payments made by you under the contract, and any negotiable instrument executed by you will be returned within TEN (10) BUSINESS DAYS following receipt by the contractor of your cancellation notice, and any security interest arising out of the transaction will be cancelled.`,
    512);
  y -= 10;

  y = addWrappedText(50, y, 10, "F2",
    `If you cancel, you must make available to the contractor at your residence, in substantially as good condition as when received, any goods delivered to you under this contract. Or you may, if you wish, comply with the instructions of the contractor regarding the return shipment of the goods at the contractor's expense and risk.`,
    512);
  y -= 10;

  y = addWrappedText(50, y, 10, "F1",
    `To cancel this transaction, mail, deliver, or email a signed and dated copy of this cancellation notice, or any other written notice to:`,
    512);
  y -= 5;

  addText(70, y, 10, "F2", contractorName);
  y -= 14;
  addText(70, y, 10, "F1", "(Contractor name and contact information as provided in this contract)");
  y -= 20;

  addText(50, y, 10, "F2", "I HEREBY CANCEL THIS TRANSACTION.");
  y -= 25;

  addText(50, y, 10, "F1", "Homeowner Signature: ___________________________________    Date: ________________");
  y -= 20;
  addText(50, y, 10, "F1", `Homeowner Name (printed): ${homeownerName}`);
  y -= 30;

  contentLines.push(`50 ${y + 5} m 562 ${y + 5} l S`);
  y -= 15;

  addText(50, y, 12, "F2", "PLATFORM DISCLOSURE");
  y -= 20;

  y = addWrappedText(50, y, 10, "F1",
    `OtterQuote is a technology platform that facilitates connections between homeowners and contractors. OtterQuote is NOT a party to this contract and assumes no liability for work performed under this agreement. This contract is between the homeowner and the contractor named above.`,
    512);
  y -= 10;

  addText(50, y, 10, "F1", `Down payment may not exceed $1,000 or 10% of contract price, whichever is less (IC 24-5-11-12).`);
  y -= 30;

  addText(50, y, 8, "F1", "This addendum is generated by OtterQuote to comply with Indiana Code IC 24-5-11 (Home Improvement Contract Act).");
  y -= 12;
  addText(50, y, 8, "F1", `Generated: ${new Date().toISOString()}`);

  const contentStream = contentLines.join("\n");
  const contentBytes = new TextEncoder().encode(contentStream);

  const pdfLines: string[] = [];
  const pdfObjects: number[] = [];
  let byteOffset = 0;

  function pdfWrite(s: string) {
    pdfLines.push(s);
    byteOffset += s.length + 1;
  }

  function pdfStartObj(n: number) {
    pdfObjects[n] = byteOffset;
    pdfWrite(`${n} 0 obj`);
  }

  pdfWrite("%PDF-1.4");

  pdfStartObj(1);
  pdfWrite("<< /Type /Catalog /Pages 2 0 R >>");
  pdfWrite("endobj");

  pdfStartObj(2);
  pdfWrite("<< /Type /Pages /Kids [3 0 R] /Count 1 >>");
  pdfWrite("endobj");

  pdfStartObj(3);
  pdfWrite("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R /F2 6 0 R >> >> >>");
  pdfWrite("endobj");

  pdfStartObj(4);
  pdfWrite(`<< /Length ${contentStream.length} >>`);
  pdfWrite("stream");
  pdfWrite(contentStream);
  pdfWrite("endstream");
  pdfWrite("endobj");

  pdfStartObj(5);
  pdfWrite("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>");
  pdfWrite("endobj");

  pdfStartObj(6);
  pdfWrite("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>");
  pdfWrite("endobj");

  const xrefOffset = byteOffset;
  pdfWrite("xref");
  pdfWrite(`0 7`);
  pdfWrite("0000000000 65535 f ");
  for (let i = 1; i <= 6; i++) {
    pdfWrite(String(pdfObjects[i]).padStart(10, "0") + " 00000 n ");
  }

  pdfWrite("trailer");
  pdfWrite(`<< /Size 7 /Root 1 0 R >>`);
  pdfWrite("startxref");
  pdfWrite(String(xrefOffset));
  pdfWrite("%%EOF");

  const pdfContent = pdfLines.join("\n");
  const pdfBytes = new TextEncoder().encode(pdfContent);
  return base64EncodeBinary(pdfBytes);
}


// ========== RETAIL SCOPE OF WORK PDF ==========
export function generateRetailScopeOfWorkPdf(params: {
  homeownerName: string;
  contractorName: string;
  propertyAddress: string;
  claimId: string;
  trades: string[];
  contractPrice: number | null;
  estimatedStartDate: string | null;
  valueAdds: any;
  bidBrand: string | null;
  deckingPricePerSheet: number | null;
  fullRedeckPrice: number | null;
  messageToHomeowner: string | null;
  homeownerNotes: string | null;
  projectConfirmation: any;
  measurements: { roofSqFt: number | null; wallSqFt: number | null; perimeterFt: number | null; pitch: string | null } | null;
  contractDate: string;
}): string {
  const {
    homeownerName, contractorName, propertyAddress, claimId,
    trades, contractPrice, estimatedStartDate, valueAdds,
    bidBrand, deckingPricePerSheet, fullRedeckPrice,
    messageToHomeowner, homeownerNotes, projectConfirmation,
    measurements, contractDate,
  } = params;

  const va = valueAdds || {};
  const pc = projectConfirmation || null;

  const pdfLines: string[] = [];
  const pdfObjects: number[] = [];
  let byteOffset = 0;

  function pdfWrite(s: string) {
    pdfLines.push(s);
    byteOffset += s.length + 1;
  }

  function pdfStartObj(n: number) {
    pdfObjects[n] = byteOffset;
    pdfWrite(`${n} 0 obj`);
  }

  const contentLines: string[] = [];

  function esc(text: string): string {
    return String(text || "").replace(/\\/g, "\\\\").replace(/\(/g, "\\(").replace(/\)/g, "\\)");
  }

  function addText(x: number, y: number, fontSize: number, font: string, text: string) {
    contentLines.push(`BT /${font} ${fontSize} Tf ${x} ${y} Td (${esc(text)}) Tj ET`);
  }

  // [D-225 Phase 2B / D-186] Render text in a chosen non-stroking gray (1.0 = white = invisible
  // on white paper). Used to embed DocuSign anchor strings without making them visible.
  function addTextColored(x: number, y: number, fontSize: number, font: string, text: string, gray: number) {
    contentLines.push(`BT ${gray} g /${font} ${fontSize} Tf ${x} ${y} Td (${esc(text)}) Tj ET 0 g`);
  }

  function addWrappedText(x: number, startY: number, fontSize: number, font: string, text: string, maxWidth: number): number {
    const charWidth = fontSize * 0.5;
    const maxChars = Math.floor(maxWidth / charWidth);
    const words = String(text || "").split(" ");
    let line = "";
    let y = startY;
    const ls = fontSize * 1.4;
    for (const word of words) {
      if (line.length + word.length + 1 > maxChars) {
        addText(x, y, fontSize, font, line.trim());
        y -= ls;
        line = word + " ";
      } else {
        line += word + " ";
      }
    }
    if (line.trim()) { addText(x, y, fontSize, font, line.trim()); y -= ls; }
    return y;
  }

  function hLine(y: number) {
    contentLines.push(`50 ${y} m 562 ${y} l S`);
  }

  function fmt$(val: number | null | undefined): string {
    if (val == null) return "TBD";
    return "$" + Number(val).toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  }

  let y = 750;

  addText(50, y, 16, "F2", "SCOPE OF WORK");
  y -= 18;
  addText(50, y, 9, "F1", `Prepared by Otter Quotes on behalf of ${esc(contractorName)}`);
  y -= 10;
  hLine(y); y -= 16;

  addText(50, y, 10, "F2", "PROJECT:");   addText(160, y, 10, "F1", esc(propertyAddress)); y -= 14;
  addText(50, y, 10, "F2", "HOMEOWNER:"); addText(160, y, 10, "F1", esc(homeownerName)); y -= 14;
  addText(50, y, 10, "F2", "CONTRACTOR:"); addText(160, y, 10, "F1", esc(contractorName)); y -= 14;
  addText(50, y, 10, "F2", "DATE:");      addText(160, y, 10, "F1", esc(contractDate)); y -= 14;
  addText(50, y, 10, "F2", "JOB REF:");   addText(160, y, 10, "F1", claimId.slice(0, 8).toUpperCase()); y -= 20;
  hLine(y); y -= 16;

  addText(50, y, 12, "F2", "CONTRACT SUMMARY"); y -= 16;
  const tradeLabel = (trades || []).map(t => t.charAt(0).toUpperCase() + t.slice(1)).join(", ") || "See below";
  addText(50, y, 10, "F2", "Trade(s):"); addText(160, y, 10, "F1", esc(tradeLabel)); y -= 14;
  addText(50, y, 10, "F2", "Financing:"); addText(160, y, 10, "F1", "Retail / Homeowner-Financed"); y -= 14;
  addText(50, y, 10, "F2", "Contract Price:"); addText(160, y, 10, "F1", contractPrice ? fmt$(contractPrice) : "Per contractor agreement"); y -= 14;
  addText(50, y, 10, "F2", "Est. Start:"); addText(160, y, 10, "F1", esc(estimatedStartDate || "To be scheduled")); y -= 20;
  hLine(y); y -= 16;

  // D-186/D-203 — Verbatim measurement disclaimer (required at top of every retail Exhibit A)
  addText(50, y, 10, "F2", "MEASUREMENT DISCLAIMER"); y -= 14;
  y = addWrappedText(50, y, 9, "F1",
    "The measurements contained in this Statement of Work were provided to Contractor on behalf of Customer. Both parties have relied upon the accuracy of this information in negotiating the terms of this Agreement. Prior to starting the work set forth in this agreement, either party shall have the right to perform his or her own measurements to verify the measurements contained herein. If any measurement in this statement of work is off by more than 10%, either party shall have the right to: (1) negotiate a change order to adjust the compensation due under the Agreement; (2) cancel the Agreement; or (3) proceed under the terms set forth in the Agreement.",
    512);
  y -= 12; hLine(y); y -= 16;

  if (measurements && (measurements.roofSqFt || measurements.wallSqFt || measurements.perimeterFt)) {
    addText(50, y, 12, "F2", "HOVER AERIAL MEASUREMENTS"); y -= 16;
    if (measurements.roofSqFt) {
      addText(50, y, 10, "F2", "Roof Area:");
      addText(160, y, 10, "F1", `${measurements.roofSqFt.toLocaleString()} sq ft (${(measurements.roofSqFt / 100).toFixed(1)} squares)`);
      y -= 14;
    }
    if (measurements.wallSqFt) {
      addText(50, y, 10, "F2", "Wall Area:");
      addText(160, y, 10, "F1", `${measurements.wallSqFt.toLocaleString()} sq ft (${(measurements.wallSqFt / 100).toFixed(1)} squares)`);
      y -= 14;
    }
    if (measurements.perimeterFt) {
      addText(50, y, 10, "F2", "Perimeter:");
      addText(160, y, 10, "F1", `${measurements.perimeterFt.toLocaleString()} linear ft`);
      y -= 14;
    }
    if (measurements.pitch) {
      addText(50, y, 10, "F2", "Primary Pitch:");
      addText(160, y, 10, "F1", esc(measurements.pitch));
      y -= 14;
    }
    y -= 6; hLine(y); y -= 16;
  }

  addText(50, y, 12, "F2", "SCOPE OF WORK DETAILS"); y -= 16;

  const hasRoofing = (trades || []).some(t => t.toLowerCase().includes("roof"));
  const hasSiding  = (trades || []).some(t => t.toLowerCase().includes("siding"));
  const hasGutters = (trades || []).some(t => t.toLowerCase().includes("gutter"));
  const hasWindows = (trades || []).some(t => t.toLowerCase().includes("window"));

  if (hasRoofing) {
    addText(50, y, 11, "F2", "ROOFING"); y -= 14;

    if (bidBrand) {
      addText(60, y, 10, "F2", "Materials:"); addText(160, y, 10, "F1", esc(bidBrand)); y -= 14;
    }
    if (pc?.shingleManufacturer || pc?.shingleColor) {
      const shingleStr = [pc.shingleManufacturer, pc.shingleColor].filter(Boolean).join(" — ");
      addText(60, y, 10, "F2", "Shingle:"); addText(160, y, 10, "F1", esc(shingleStr)); y -= 14;
    }
    if (pc?.dripEdgeColor) {
      addText(60, y, 10, "F2", "Drip Edge Color:"); addText(160, y, 10, "F1", esc(pc.dripEdgeColor)); y -= 14;
    }
    if (va.underlayment?.type) {
      addText(60, y, 10, "F2", "Underlayment:");
      addText(160, y, 10, "F1", va.underlayment.type === "synthetic" ? "Synthetic" : "Felt");
      y -= 14;
    }
    if (va.starter_strip) {
      const ssMap: Record<string, string> = { rakes: "Rakes only", eaves: "Eaves only", rakes_and_eaves: "Rakes and Eaves", neither: "None" };
      addText(60, y, 10, "F2", "Starter Strip:"); addText(160, y, 10, "F1", ssMap[va.starter_strip] || esc(va.starter_strip)); y -= 14;
    }
    if (va.ventilation) {
      const ventDesc = va.ventilation.ridge_vent_included
        ? "Ridge Vent — Included"
        : va.ventilation.ridge_vent_oop
        ? `Ridge Vent — OOP ${fmt$(va.ventilation.ridge_vent_oop)}`
        : null;
      if (ventDesc) { addText(60, y, 10, "F2", "Ventilation:"); addText(160, y, 10, "F1", ventDesc); y -= 14; }
    }
    if (deckingPricePerSheet) {
      const redeckTxt = fullRedeckPrice
        ? `${fmt$(deckingPricePerSheet)}/sheet if needed; Full redeck: ${fmt$(fullRedeckPrice)}`
        : `${fmt$(deckingPricePerSheet)}/sheet if needed`;
      addText(60, y, 10, "F2", "Decking:");
      y = addWrappedText(160, y, 10, "F1", redeckTxt, 380);
    }
    if (va.chimney_flashing?.option && va.chimney_flashing.option !== "na") {
      const cfMap: Record<string, string> = { reuse: "Reuse existing", replace: "Replace — Included", replace_oop: `Replace OOP ${fmt$(va.chimney_flashing.oop_price)}` };
      addText(60, y, 10, "F2", "Chimney Flashing:"); addText(160, y, 10, "F1", cfMap[va.chimney_flashing.option] || esc(va.chimney_flashing.option)); y -= 14;
    }
    if (va.skylights && va.skylights !== "na") {
      addText(60, y, 10, "F2", "Skylights:"); addText(160, y, 10, "F1", va.skylights === "reflash" ? "Reflash" : "Replace"); y -= 14;
    }
    if (pc?.valleyType) {
      addText(60, y, 10, "F2", "Valleys:"); addText(160, y, 10, "F1", pc.valleyType === "closed" ? "Closed Cut" : "Open / Metal"); y -= 14;
    }
    if (pc?.gutterGuards) {
      addText(60, y, 10, "F2", "Gutter Guards:"); addText(160, y, 10, "F1", esc(pc.gutterGuards)); y -= 14;
    }
    if (pc?.satelliteDish && pc.satelliteDish !== "NONE") {
      const satMap: Record<string, string> = { "REMOVE-TRASH": "Remove & discard", "REMOVE-RESET": "Remove & reset after install" };
      addText(60, y, 10, "F2", "Satellite Dish:"); addText(160, y, 10, "F1", satMap[pc.satelliteDish] || esc(pc.satelliteDish)); y -= 14;
    }
    y -= 8;
  }

  const slc = va?.secondLayerContingency;
  if (hasRoofing && slc) {
    const slcAmount = (slc.method === "flat_fee" && slc.flatFeeAlternative != null)
      ? slc.flatFeeAlternative
      : slc.pricePerSquare;
    if (slcAmount != null) {
      const slcPhrase = slc.method === "flat_fee" ? "flat fee" : "per square";
      const slcDisclaimer =
        `If the existing roof is found to contain more than one layer of shingles, the contract price will increase by ${fmt$(slcAmount)} ${slcPhrase}. ` +
        `Customer will be notified before work proceeds and has the right to accept the change order or cancel the Agreement per the Change Order Disclaimer.`;
      addText(50, y, 11, "F2", "SECOND-LAYER TEAR-OFF CONTINGENCY"); y -= 14;
      y = addWrappedText(60, y, 10, "F1", slcDisclaimer, 480);
      y -= 8;
    }
  }

  if (hasGutters) {
    addText(50, y, 11, "F2", "GUTTERS"); y -= 14;

    if (va.gutters?.option) {
      const go = va.gutters.option;
      let gutterDesc = esc(go);
      if (go === "5inch_included" || go === "5inch") gutterDesc = '5" Gutters — Included';
      else if (go === "6inch_included" || go === "6inch") gutterDesc = '6" Gutters — Included';
      else if (go.includes("5inch") && go.includes("additional")) gutterDesc = `5" Gutters — OOP ${fmt$(va.gutters.additional_cost_5inch)}`;
      else if (go.includes("6inch") && go.includes("additional")) gutterDesc = `6" Gutters — OOP ${fmt$(va.gutters.additional_cost_6inch)}`;
      else if (go === "none") gutterDesc = "No gutter work included";
      addText(60, y, 10, "F2", "Gutters:"); addText(160, y, 10, "F1", gutterDesc); y -= 14;
    }

    if (va.gutter_guards) {
      const gg = va.gutter_guards;
      if (gg.pricing_on_request) {
        addText(60, y, 10, "F2", "Gutter Guards:"); addText(160, y, 10, "F1", "Available — pricing on request"); y -= 14;
      } else if (gg.mesh_oop || gg.screw_in_oop) {
        const parts: string[] = [];
        if (gg.mesh_oop) parts.push(`Mesh OOP ${fmt$(gg.mesh_oop)}`);
        if (gg.screw_in_oop) parts.push(`Screw-in OOP ${fmt$(gg.screw_in_oop)}`);
        addText(60, y, 10, "F2", "Gutter Guards:"); addText(160, y, 10, "F1", parts.join("; ")); y -= 14;
      }
    }
    y -= 8;
  }

  if (hasSiding) {
    addText(50, y, 11, "F2", "SIDING"); y -= 14;
    addText(60, y, 10, "F1", "Scope per contractor bid and Hover design specifications."); y -= 14;
    if (measurements?.wallSqFt) {
      addText(60, y, 10, "F2", "Wall Area:"); addText(160, y, 10, "F1", `${(measurements.wallSqFt / 100).toFixed(1)} squares`); y -= 14;
    }
    y -= 8;
  }

  if (hasWindows) {
    addText(50, y, 11, "F2", "WINDOWS"); y -= 14;
    addText(60, y, 10, "F1", "Scope per contractor bid."); y -= 14;
    y -= 8;
  }

  if (Array.isArray(va.warranties) && va.warranties.length > 0) {
    hLine(y + 4); y -= 12;
    addText(50, y, 12, "F2", "WARRANTIES"); y -= 14;
    for (const w of va.warranties) {
      if (!w.name) continue;
      addText(60, y, 10, "F2", esc(w.name)); y -= 12;
      if (w.material_defects?.years) { addText(70, y, 9, "F1", `Material Defects: ${w.material_defects.years} yrs`); y -= 11; }
      if (w.labor?.years) { addText(70, y, 9, "F1", `Labor: ${w.labor.years} yrs`); y -= 11; }
      if (w.wind_damage?.years) { addText(70, y, 9, "F1", `Wind: ${w.wind_damage.years} yrs`); y -= 11; }
      if (w.hail_damage?.years) { addText(70, y, 9, "F1", `Hail: ${w.hail_damage.years} yrs`); y -= 11; }
      y -= 4;
    }
  }

  const hasNotes = homeownerNotes || messageToHomeowner || va.other_offers ||
                   (pc?.workNotBeingDone) || (pc?.homeownerNotes);
  if (hasNotes) {
    hLine(y + 4); y -= 12;
    addText(50, y, 12, "F2", "NOTES"); y -= 14;
    if (homeownerNotes) {
      addText(50, y, 10, "F2", "Homeowner Notes:"); y -= 12;
      y = addWrappedText(60, y, 9, "F1", homeownerNotes, 500); y -= 4;
    }
    if (messageToHomeowner) {
      addText(50, y, 10, "F2", "Message from Contractor:"); y -= 12;
      y = addWrappedText(60, y, 9, "F1", messageToHomeowner, 500); y -= 4;
    }
    if (va.other_offers) {
      addText(50, y, 10, "F2", "Special Offers:"); y -= 12;
      y = addWrappedText(60, y, 9, "F1", va.other_offers, 500); y -= 4;
    }
    if (pc?.workNotBeingDone) {
      addText(50, y, 10, "F2", "Exclusions:"); y -= 12;
      y = addWrappedText(60, y, 9, "F1", pc.workNotBeingDone, 500); y -= 4;
    }
    if (pc?.homeownerNotes) {
      addText(50, y, 10, "F2", "Project Notes:"); y -= 12;
      y = addWrappedText(60, y, 9, "F1", pc.homeownerNotes, 500);
    }
  }

  // [D-225 Phase 2B / D-186] Dual-party initials anchor row.
  // The labels (Contractor Initial: ___ / Homeowner Initial: ___) are visible to humans;
  // the /ContractorInitial/ and /HomeownerInitial/ anchor strings are drawn in white at the
  // same x-position so they are invisible on the rendered page but findable by DocuSign's
  // text-extraction anchor parser. DocuSign overlays each party's initials at the anchor.
  y -= 18; hLine(y + 4); y -= 16;
  addText(50,  y, 10, "F2", "Initials:");
  addText(115, y, 10, "F1", "Contractor:");
  addText(180, y, 10, "F1", "_________");
  addTextColored(180, y, 10, "F1", "/ContractorInitial/", 1.0);
  addText(320, y, 10, "F1", "Homeowner:");
  addText(390, y, 10, "F1", "_________");
  addTextColored(390, y, 10, "F1", "/HomeownerInitial/", 1.0);
  y -= 4;

  y -= 12; hLine(y + 4); y -= 12;
  y = addWrappedText(50, y, 8, "F1",
    "This Scope of Work is a reference document generated by Otter Quotes. The contractor's signed agreement is the binding contract. Scope details are based on the contractor's bid submission and may be supplemented by on-site assessment.",
    512);
  addText(50, y, 8, "F1", `Generated by Otter Quotes on ${esc(contractDate)} — Job Ref ${claimId.slice(0, 8).toUpperCase()}`);

  const contentStream = contentLines.join("\n");

  pdfWrite("%PDF-1.4");

  pdfStartObj(1);
  pdfWrite("<< /Type /Catalog /Pages 2 0 R >>");
  pdfWrite("endobj");

  pdfStartObj(2);
  pdfWrite("<< /Type /Pages /Kids [3 0 R] /Count 1 >>");
  pdfWrite("endobj");

  pdfStartObj(3);
  pdfWrite("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R /F2 6 0 R >> >> >>");
  pdfWrite("endobj");

  pdfStartObj(4);
  pdfWrite(`<< /Length ${contentStream.length} >>`);
  pdfWrite("stream");
  pdfWrite(contentStream);
  pdfWrite("endstream");
  pdfWrite("endobj");

  pdfStartObj(5);
  pdfWrite("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>");
  pdfWrite("endobj");

  pdfStartObj(6);
  pdfWrite("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>");
  pdfWrite("endobj");

  const xrefOffset = byteOffset;
  pdfWrite("xref");
  pdfWrite("0 7");
  pdfWrite("0000000000 65535 f ");
  for (let i = 1; i <= 6; i++) {
    pdfWrite(String(pdfObjects[i]).padStart(10, "0") + " 00000 n ");
  }
  pdfWrite("trailer");
  pdfWrite("<< /Size 7 /Root 1 0 R >>");
  pdfWrite("startxref");
  pdfWrite(String(xrefOffset));
  pdfWrite("%%EOF");

  return base64EncodeBinary(new TextEncoder().encode(pdfLines.join("\n")));
}

