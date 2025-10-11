/* eslint-disable no-console */
const functions = require("firebase-functions");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");

admin.initializeApp();

// Read Gmail config from functions config
const cfg = functions.config() || {};
const gmailCfg = cfg.gmail || {};
const GMAIL_USER = gmailCfg.user || null;
const GMAIL_PASS = gmailCfg.pass || null;

// Create transporter only when credentials are present
let transporter = null;
if (GMAIL_USER && GMAIL_PASS) {
  transporter = nodemailer.createTransport({
    service: "gmail",
    auth: {
      user: GMAIL_USER,
      pass: GMAIL_PASS,
    },
  });
}

exports.handleApproval = functions.https.onRequest(async (req, res) => {
  try {
    const token = req.query.token;
    const action = (req.query.action || "").toLowerCase();
    const reason = req.query.reason || null; // Optional reason for resubmission

    if (!token || (action !== "approve" && action !== "resubmission")) {
      return res.status(400).send("Invalid request");
    }

    const tokenRef = admin
        .firestore()
        .collection("approvalTokens")
        .doc(token);
    const tokenSnap = await tokenRef.get();
    if (!tokenSnap.exists) return res.status(404).send("Token not found");

    const tokenData = tokenSnap.data() || {};
    if (tokenData.used === true) return res.status(410).send("Token used");

    if (
      tokenData.expiresAt &&
      typeof tokenData.expiresAt.toDate === "function"
    ) {
      if (tokenData.expiresAt.toDate() < new Date()) {
        await tokenRef.update({
          used: true,
          usedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return res.status(410).send("Token expired");
      }
    }

    const userId = tokenData.userId;
    if (!userId) return res.status(400).send("Token missing userId");

    const userRef = admin.firestore().collection("users").doc(userId);
    const userSnap = await userRef.get();
    const user = userSnap.data() || {};
    if (user.approvalStatus !== 'pending') return res.status(400).send("User not pending");

    const ownerEmail = user.email || '';
    const ownerName = user.name || "Owner";
    const stationName = user.stationName || "Unknown Station";

    if (!ownerEmail) return res.status(400).send("No owner email found");

    // 1) Send confirmation email to owner FIRST
    const status = action === "approve" ? "Approved" : "Resubmission";
    const subject = action === "approve"
      ? 'FuelGo Registration APPROVED - Welcome to FuelGo!'
      : 'FuelGo Registration - Document Review Required';

    let htmlBody;
    if (action === "approve") {
      htmlBody = `
        <p>Dear ${ownerName},</p>
        <p>Congratulations! Your gas station registration has been <strong>APPROVED</strong>.</p>
        <br>
        <p><strong>Your Registration Details:</strong></p>
        <ul>
          <li>Name: ${ownerName}</li>
          <li>Station: ${stationName}</li>
          <li>Status: APPROVED</li>
        </ul>
        <br>
        <p><strong>Next Steps:</strong></p>
        <p>You can now log into your owner account and start managing your gas station. Upload fuel prices, manage inventory, and serve customers through the FuelGo platform.</p>
        <br>
        <p>If you have any questions or need assistance, don't hesitate to reply to this email.</p>
        <br>
        <p>Best regards,<br/>
        The FuelGo Team<br/>
        FuelGo System Admin</p>
      `;
    } else {
      htmlBody = `
        <p>Dear ${ownerName},</p>
        <p>Your registration requires document review.</p>
        <br>
        <p><strong>Details:</strong></p>
        <ul>
          <li>Name: ${ownerName}</li>
          <li>Station: ${stationName}</li>
          <li>Status: Resubmission</li>
        </ul>
        <br>
        ${reason ? `<p><strong>Reason:</strong> ${reason}<br/><br/></p>` : ''}
        <p>Please resubmit with clearer documents (check for blurry images, expired IDs, or missing info).</p>
        <br>
        <p>Reply if you have questions.</p>
        <br>
        <p>Best regards,<br/>
        The FuelGo Team</p>
      `;
    }

    const mailOptions = {
      from: GMAIL_USER,
      to: ownerEmail,
      subject: subject,
      html: htmlBody,
    };

    let emailSent = false;
    if (transporter) {
      try {
        await transporter.sendMail(mailOptions);
        console.log("Owner confirmation email sent to", ownerEmail);
        emailSent = true;
      } catch (sendErr) {
        console.error("Error sending owner email:", sendErr);
        emailSent = false;
      }
    } else {
      console.log("Gmail not configured - skipping owner email.");
      emailSent = false;
    }

    if (!emailSent) {
      return res.status(500).send("Failed to send owner notification email. Status remains pending.");
    }

    // 2) If email succeeds, update Firestore atomically with transaction
    await admin.firestore().runTransaction(async (transaction) => {
      const freshTokenSnap = await transaction.get(tokenRef);
      const freshTokenData = freshTokenSnap.data() || {};
      if (freshTokenData.used === true || !freshTokenSnap.exists) {
        throw new Error("Token invalid or already used");
      }

      const freshUserSnap = await transaction.get(userRef);
      const freshUser = freshUserSnap.data() || {};
      if (freshUser.approvalStatus !== 'pending') {
        throw new Error("User not pending");
      }

      // Update user
      const updateData = {
        approvalStatus: status,
        emailNotificationSent: true,
        approvalProcessedVia: "emailLink",
        approvalProcessedAt: admin.firestore.FieldValue.serverTimestamp(),
        approvalAction: action,
      };
      if (action === "approve") {
        updateData.approvedAt = admin.firestore.FieldValue.serverTimestamp();
      } else {
        updateData.requestSubmissionAt = admin.firestore.FieldValue.serverTimestamp();
        if (reason) {
          updateData.rejectionReason = reason;
        }
      }
      transaction.update(userRef, updateData);

      // Update token
      transaction.update(tokenRef, {
        used: true,
        usedAt: admin.firestore.FieldValue.serverTimestamp(),
        action: action,
      });
    });

    // Friendly HTML response for admin clicking the link
    const resultHtml = `
      <html>
      <head>
        <meta name="viewport" content="width=device-width, initial-scale=1"/>
      </head>
      <body style="font-family: Arial, sans-serif; padding: 40px; text-align: center;">
        <h1>Success!</h1>
        <p>User has been <strong>${status}</strong> successfully.</p>
        <p>Owner notified via email. You can close this window.</p>
      </body>
      </html>
    `;

    return res.status(200).send(resultHtml);
  } catch (err) {
    console.error("handleApproval error", err);
    return res.status(500).send("Server error: " + err.message);
  }
});
