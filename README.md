<div dir="rtl">

# الكيف الأصلي — Kaif Original

**الكيف الأصلي** نظام متكامل لتخطيط موارد المؤسسات (ERP) وإدارة علاقات العملاء (CRM)، موجّه للشركات الصغيرة والمتوسطة في المملكة العربية السعودية. يضم المخزون والفوترة والمبيعات والمشتريات والتصنيع والمشاريع والموارد البشرية ونقاط البيع في تطبيق واحد وقاعدة بيانات واحدة.

## ما يميز الكيف الأصلي

- **واجهة عربية**: جميع نصوص التطبيق مترجمة إلى العربية، واللغة الافتراضية هي العربية.
- **إضافة السعودية** (`src/main/lsfusion/region/sa`):
  - ضريبة القيمة المضافة 15% و0% والمعفى.
  - الرقم الضريبي للشركاء مع التحقق من صحته (15 رقماً يبدأ وينتهي بالرقم 3)، ورقم السجل التجاري، والعنوان الوطني.
  - رمز QR الخاص بهيئة الزكاة والضريبة والجمارك (المرحلة الأولى من الفوترة الإلكترونية).
  - فاتورة ضريبية وفاتورة ضريبية مبسطة بالعربية والإنجليزية.
- **البيع الآجل والرقابة الائتمانية**: حد ائتماني وأقصى أيام تأخير لكل عميل (أو قيم افتراضية من إعدادات الفوترة)، ومنع ترحيل الفاتورة عند تجاوزهما، مع إمكانية الاستثناء لفاتورة محددة.
- **هوية الكيف الأصلي**: الاسم، والألوان الخضراء والبيضاء في واجهة الويب.

## الوحدات

المبيعات وإدارة العملاء، المشتريات والمخزون، الفوترة والمدفوعات، المحاسبة، التصنيع، المشاريع، الموارد البشرية والرواتب، نقاط البيع، والأسطول.

## التشغيل

1. ثبّت منصة lsFusion 7 وقاعدة PostgreSQL.
2. عدّل بيانات قاعدة البيانات في `conf/settings.properties`، **وغيّر كلمة المرور الافتراضية**.
3. الوحدة الرئيسية هي `MyCompanySa`، ومحددة في `src/main/resources/lsfusion.properties`.
4. واجهة الويب على المنفذ 8080.

بعد أول تشغيل، أدخل في بطاقة شركتك: **الرقم الضريبي** و**السجل التجاري** و**العنوان الوطني**، لتظهر في الفواتير وفي رمز QR.

## الترخيص

الكيف الأصلي مبني على مشروع [MyCompany](https://github.com/lsfusion-solutions/mycompany) مفتوح المصدر من lsFusion، وهو مرخّص بموجب [Apache License 2.0](LICENSE). منصة lsFusion مرخّصة بشكل منفصل بموجب LGPL v3.

</div>

---

# Kaif Original (Al-Kaif Al-Asli)

Kaif Original is an ERP and CRM for small and medium-sized businesses in Saudi Arabia: inventory, invoicing, sales, purchasing, manufacturing, projects, HR and retail POS in one application with a single database.

- **Arabic interface**: all application strings are translated into Arabic, which is the default language.
- **Saudi Arabia localization** (`src/main/lsfusion/region/sa`): VAT 15% / 0% / exempt, validated VAT numbers, CR numbers and national addresses on partners, the ZATCA phase 1 QR code, and a bilingual tax invoice / simplified tax invoice.
- **Credit control**: a credit limit and maximum overdue days per customer (or defaults from the invoicing settings); posting an invoice that exceeds them is blocked, with a per-invoice override.
- **Kaif Original branding**: the application name and a green and white web theme (`src/main/resources/web/kaif/kaif-theme.css`).

The top module is `MyCompanySa` (`src/main/resources/lsfusion.properties`). Before production use, change the default database password in `conf/settings.properties`.

Kaif Original is based on the open-source [MyCompany](https://github.com/lsfusion-solutions/mycompany) by lsFusion, licensed under the [Apache License 2.0](LICENSE). The underlying lsFusion platform is licensed separately under LGPL v3.
