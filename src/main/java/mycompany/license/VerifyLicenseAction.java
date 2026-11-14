package mycompany.license;

import lsfusion.server.data.sql.exception.SQLHandledException;
import lsfusion.server.language.ScriptingLogicsModule;
import lsfusion.server.logics.action.controller.context.ExecutionContext;
import lsfusion.server.logics.classes.ValueClass;
import lsfusion.server.logics.property.classes.ClassPropertyInterface;
import lsfusion.server.physics.dev.integration.internal.to.InternalAction;

import java.sql.SQLException;
import java.util.Map;

/** verifyLicense(TEXT key): sets licenseCheckValid[], licenseCheckLicensee[], licenseCheckExpires[] (see TrialSa.lsf). */
public class VerifyLicenseAction extends InternalAction {

    public VerifyLicenseAction(ScriptingLogicsModule LM, ValueClass... classes) {
        super(LM, classes);
    }

    @Override
    protected void executeInternal(ExecutionContext<ClassPropertyInterface> context) throws SQLException, SQLHandledException {
        String key = (String) getParam(0, context);
        Map<String, String> fields = LicenseVerifier.verify(key);
        try {
            findProperty("licenseCheckValid[]").change(fields != null ? true : null, context);
            findProperty("licenseCheckLicensee[]").change(fields != null ? fields.get("licensee") : null, context);
            findProperty("licenseCheckExpires[]").change(fields != null ? fields.get("expires") : null, context);
        } catch (Exception e) {
            throw new RuntimeException("License verification error", e);
        }
    }
}
