/**
 * This groovy script directly run by groovy commands inside active choices reactive parameters of jenkins jobs.
 * It does the "grunt" work of loading on to the classpath the jar file that produces the html for those parameters.
 * Also, methods calls are proxied to that resources in that jar using reflection.
 * A typical active choices reactive parameter body that makes such a call will look something like this:
 *
 *  
 */


import java.lang.reflect.Method;
import org.codehaus.groovy.runtime.ReflectionMethodInvoker ;

def getHtml(className, methodName, parmName, parmMap) {
  try {
    URL[] urls = [new File("/var/lib/jenkins/.groovy/lib/kuali-jenkins-ui.jar").toURI().toURL()] as URL[];
    URLClassLoader loader = new URLClassLoader(urls, this.class.classLoader);

    Class parmObjClass = Class.forName("org.bu.jenkins.job.AbstractJob\$ParameterConfiguration", true, loader);
    Object parms = [parmName, parmMap] as Object[];
    Object[] parmObj = ReflectionMethodInvoker.invoke(parmObjClass, "forActiveChoicesFragmentInstance", parms);

    Class classToLoad = Class.forName(className, true, loader);
    Object instance = classToLoad.newInstance();
    return (String) ReflectionMethodInvoker.invoke(instance, methodName, parmObj);
  }
  catch(Exception e) {
    StringWriter sw = new StringWriter();
    PrintWriter pw = new PrintWriter(sw);
    if(e.getMessage() != null) {
      pw.write(e.getMessage());
    }
    pw.write("\n");
    e.printStackTrace(pw);
    return "<pre>" + sw.toString() + "</pre>";
  }
}

def getHtml(className, methodName, parmName) {
  return getHtml(className, methodName, parmName, new HashMap());
}

