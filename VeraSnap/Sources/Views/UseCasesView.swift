//
//  UseCasesView.swift
//  VeraSnap
//
//  Use Cases Gallery
//  © 2026 VeritasChain株式会社
//

import SwiftUI

// MARK: - Use Case Category

struct UseCaseCategory: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let color: Color
    let cases: [UseCase]
}

struct UseCase: Identifiable {
    let id = UUID()
    let title: String
    let description: String
}

// MARK: - Use Cases Data

struct UseCasesData {
    static let categories: [UseCaseCategory] = [
        UseCaseCategory(
            icon: "banknote",
            title: "金融・保険",
            color: .green,
            cases: [
                UseCase(title: "保険請求", description: "事故現場の写真が「本当にその場で、本人が撮影した」ことを証明。保険詐欺の防止と正当な請求の迅速化を両立"),
                UseCase(title: "本人確認・KYC", description: "「今、この場所に、この人物がいる」ことの証明。リモート本人確認の信頼性を革新的に向上"),
                UseCase(title: "融資審査", description: "担保物件や事業所の現況を融資担当者が実地確認したことの証明"),
                UseCase(title: "不動産鑑定", description: "鑑定士が実際に物件を訪問し、状態を確認したことの証明"),
            ]
        ),
        UseCaseCategory(
            icon: "building.2",
            title: "不動産・建設",
            color: .orange,
            cases: [
                UseCase(title: "不動産取引", description: "物件の現状写真が「実際に内見した人が撮影した」ことを証明。退去時トラブルや現状確認の紛争を防止"),
                UseCase(title: "工事進捗管理", description: "現場監督が実際に現場で施工状況を確認したことを証明。竣工検査の信頼性向上"),
                UseCase(title: "設備点検記録", description: "点検員が実際に現場で設備の状態を確認したことを証明。安全管理の徹底"),
                UseCase(title: "インフラ劣化診断", description: "技術者が橋梁・トンネル・道路などの損傷箇所を実地で確認したことの証明"),
            ]
        ),
        UseCaseCategory(
            icon: "newspaper",
            title: "報道・法務",
            color: .blue,
            cases: [
                UseCase(title: "ジャーナリズム", description: "報道写真が「現場にいた記者が撮影した」ことを証明。フェイクニュース対策の決定打"),
                UseCase(title: "法的証拠", description: "裁判における写真・動画証拠の証拠能力を大幅に向上。「誰が撮影したか分からない」という反論を封じる"),
                UseCase(title: "現地調査の証跡", description: "弁護士・調査員が実際に現場視察を実施したことの証明"),
                UseCase(title: "知的財産侵害", description: "特許・商標侵害を発見者が実際に現場で確認したことの証明"),
            ]
        ),
        UseCaseCategory(
            icon: "cross.case",
            title: "医療・ヘルスケア",
            color: .red,
            cases: [
                UseCase(title: "医療記録", description: "医師や看護師が実際に患者の患部を撮影・確認したことを証明。遠隔医療での診断精度向上"),
                UseCase(title: "臨床試験", description: "治験コーディネーターが薬剤投与や患者状態を実際に目視確認したことの証明"),
                UseCase(title: "在宅医療", description: "ケアマネージャーや訪問看護師が実際に患者宅を訪問したことの証明"),
            ]
        ),
        UseCaseCategory(
            icon: "gearshape.2",
            title: "製造・品質管理",
            color: .purple,
            cases: [
                UseCase(title: "製品検査", description: "検査員が実際に製品を目視検査したことを証明。品質保証の信頼性向上"),
                UseCase(title: "トレーサビリティ", description: "製造工程の各段階で人間が確認したことを記録。食品・医薬品の安全管理"),
                UseCase(title: "出荷前検品", description: "物流担当者が実際に商品状態を確認してから発送したことの証明"),
            ]
        ),
        UseCaseCategory(
            icon: "graduationcap",
            title: "教育",
            color: .cyan,
            cases: [
                UseCase(title: "遠隔試験", description: "受験者本人が実際に試験会場または自宅で受験していることの証明"),
                UseCase(title: "フィールドワーク", description: "学生が実際に現地調査や実験を行ったことの証明"),
                UseCase(title: "出席確認", description: "学生が実際に授業会場に物理的に出席していることの証明"),
            ]
        ),
        UseCaseCategory(
            icon: "building.columns",
            title: "行政・公共",
            color: .indigo,
            cases: [
                UseCase(title: "行政現地調査", description: "公務員が実際に現場視察や行政調査を実施したことの証明"),
                UseCase(title: "災害状況報告", description: "被災地の状況を職員が実地で確認・撮影したことの証明"),
                UseCase(title: "施設管理", description: "巡回員が実際に道路・公園施設の状態を確認したことの記録"),
            ]
        ),
        UseCaseCategory(
            icon: "leaf",
            title: "環境・農業",
            color: .green,
            cases: [
                UseCase(title: "環境モニタリング", description: "調査員が実際に現地で環境状態を観測したことの証明"),
                UseCase(title: "農作物管理", description: "生産者が実際に圃場で作物の状態を確認したことの証明。有機認証への応用"),
                UseCase(title: "野生動物調査", description: "研究者が実際に現地で動植物を観察・記録したことの証明"),
            ]
        ),
        UseCaseCategory(
            icon: "shield.checkered",
            title: "セキュリティ・警備",
            color: .gray,
            cases: [
                UseCase(title: "警備巡回", description: "警備員が実際に巡回ルートを回り、各所を確認したことの証明"),
                UseCase(title: "施設点検", description: "防災設備や消防設備を担当者が実地で点検したことの証明"),
                UseCase(title: "入退室管理", description: "特定エリアに本人が実際に入室したことの証明"),
            ]
        ),
        UseCaseCategory(
            icon: "shippingbox",
            title: "小売・物流",
            color: .brown,
            cases: [
                UseCase(title: "納品・配送", description: "配達員が実際に商品を届け、受け取り状態を確認したことの証明"),
                UseCase(title: "店舗巡回", description: "スーパーバイザーが実際に各店舗を訪問し、運営状況を確認したことの証明"),
                UseCase(title: "在庫棚卸", description: "担当者が実際に倉庫で在庫を確認したことの証明"),
            ]
        ),
        UseCaseCategory(
            icon: "car",
            title: "自動車・モビリティ",
            color: .mint,
            cases: [
                UseCase(title: "事故鑑定", description: "鑑定人が実際に事故現場で車両損傷を確認したことの証明"),
                UseCase(title: "中古車査定", description: "査定士が実際に車両の状態を確認したことの証明。走行距離改ざん対策"),
                UseCase(title: "レンタカー", description: "スタッフと利用者が車両状態を確認したことの双方向証明"),
            ]
        ),
        UseCaseCategory(
            icon: "pawprint",
            title: "ペット・動物",
            color: .pink,
            cases: [
                UseCase(title: "ペット預かり", description: "ペットシッターが実際にペットの世話をしたことの証明"),
                UseCase(title: "動物病院", description: "獣医師が実際にペットを診察したことの証明"),
                UseCase(title: "飼育環境", description: "購入希望者が実際にブリーダーの飼育施設を確認したことの証明"),
            ]
        ),
    ]
}

// MARK: - Use Cases View

struct UseCasesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var expandedCategory: UUID?
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // ヘッダー説明
                    headerSection
                    
                    // カテゴリ一覧
                    ForEach(UseCasesData.categories) { category in
                        CategoryCard(
                            category: category,
                            isExpanded: expandedCategory == category.id
                        ) {
                            withAnimation(.spring(response: 0.3)) {
                                if expandedCategory == category.id {
                                    expandedCategory = nil
                                } else {
                                    expandedCategory = category.id
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("ユースケース")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.fill.viewfinder")
                    .font(.title2)
                    .foregroundStyle(
                        LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                
                Text("人間の存在を証明する")
                    .font(.headline)
            }
            
            Text("VeraSnapの「人間の存在バインディング」技術により、従来は証明が困難だった「実際に現場で人が確認した」という事実を暗号学的に証明できます。")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineSpacing(4)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
}

// MARK: - Category Card

struct CategoryCard: View {
    let category: UseCaseCategory
    let isExpanded: Bool
    let onTap: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            Button(action: onTap) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(category.color.opacity(0.15))
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: category.icon)
                            .font(.title3)
                            .foregroundColor(category.color)
                    }
                    
                    Text(category.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text("\(category.cases.count)件")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.systemBackground))
            }
            .buttonStyle(.plain)
            
            // 展開時のコンテンツ
            if isExpanded {
                VStack(spacing: 0) {
                    Divider()
                    
                    ForEach(category.cases) { useCase in
                        UseCaseRow(useCase: useCase)
                        
                        if useCase.id != category.cases.last?.id {
                            Divider()
                                .padding(.leading, 16)
                        }
                    }
                }
                .background(Color(.systemBackground))
            }
        }
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }
}

// MARK: - Use Case Row

struct UseCaseRow: View {
    let useCase: UseCase
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(useCase.title)
                .font(.subheadline)
                .fontWeight(.medium)
            
            Text(useCase.description)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineSpacing(2)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Preview

#Preview {
    UseCasesView()
}
