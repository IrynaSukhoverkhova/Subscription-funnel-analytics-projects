Script §3.8 - Black Friday cohort analysis (Python)

import io, matplotlib.pyplot as plt, numpy as np, pandas as pd
raw_data = """month total_spend total_revenue
2024-02 6601 11739 ... 2025-08 10171 4726"""   # 19 monthly rows
df = pd.read_csv(io.StringIO(raw_data), sep="\t")
df["profit"] = df["total_revenue"] - df["total_spend"]   # identify unprofitable months
fig, ax1 = plt.subplots(figsize=(14,7), dpi=100)
x = np.arange(len(df["month"]))
ax1.bar(x, df["total_spend"], color="#5492f2", label="Total Spend")
ax1.plot(x, df["total_revenue"], color="#e65c00", lw=3, marker="o", label="Total Revenue")
for i,row in df.iterrows():
    if row["profit"] < 0: ax1.axvspan(i-0.4, i+0.4, color="#FFCDD2", alpha=0.5)  # highlight losses
plt.title("Financial Performance: Spend vs Revenue Trend"); plt.savefig("financial_report.png", dpi=300)

________________________________________________________________________

Scripts §3.11 - value-to-cost, plan mix, revenue heatmap (Python)

# Strategic Value-to-Cost Matrix (all 7 channels)
channels = ['ASO Organic','Apple Search Ads','Influencer','Facebook Ads','Google Ads','TikTok Ads','Referral']
payback_period     = [0.5, 2.1, 0.6, 4.5, 6.2, 7.5, 8.5]
subscription_ratio = [0.70, 0.60, 0.40, 0.45, 0.30, 0.15, 0.25]
scalability        = [5, 4, 1, 5, 4, 3, 2]      # bubble size
# quadrant dividers: x=4.0 (payback), y=0.40 (annual ratio)

# Subscription Plan Mix
annual_subs  = np.array([225, 415, 338, 76])   # Influencers / ASA / Google / TikTok
monthly_subs = np.array([96, 277, 790, 680])   # annual share 70/60/30/10 %

# Geographic Revenue Heatmap
data = {"US":[42000,35000,5000,4000,2000], "UK":[18500,21000,3000,2000,1500],
        "DE":[8000,6000,24000,3000,1000], "BR":[4000,3000,1000,12000,2000],
        "PL":[2000,1500,1000,3000,14000]}
# rows: Facebook, Google, Apple Search, TikTok, Influencers  ·  cmap="YlGnBu"

__________________________________________________________________________

Script §3.12 - refund leakage & CRM analysis (Python)

import matplotlib.pyplot as plt, seaborn as sns, pandas as pd
refund_data = pd.DataFrame({'Plan':['P02','P04','P05','P03'],'Refund_Amount':[780.63,631.36,262.48,102.56]})
crm_data = pd.DataFrame({'Campaign':['Email','Push Notification','Win-back'],
    'Renewal':[129,92,42], 'Upgrade':[36,18,0], 'First Payment':[0,0,22]})
fig, axes = plt.subplots(1,2, figsize=(15,6))
sns.barplot(data=refund_data, x='Plan', y='Refund_Amount', ax=axes[0], color='#334155')
axes[0].set_title('Refund Leakage by Subscription Plan ($)')
crm_data.set_index('Campaign').plot(kind='bar', stacked=True, ax=axes[1], color=['#475569','#3b82f6','#94a3b8'])
axes[1].set_title('CRM Campaign Impact by Transaction Type'); plt.show()
